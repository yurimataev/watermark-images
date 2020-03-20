#!/usr/bin/perl

use strict;
use Socket;
use GD;
use Image::Resize;
use POSIX;

# CONFIG
my $backup_dir      = '/path/to/backup/dir';
my $watermark_image = '/path/to/watermark/file/watermark.png';
# Do not watermark images smaller than (pixels):
my $min_height = 75;
my $min_width  = 200;
# CONFIG END, no need to edit beyond this line

my $basepath = $ARGV[0];
my $command  = $ARGV[1];

if (!$basepath) {
  die "Usage: watermark-images.pl /path/to/image/dir [safe|restore]
safe    - make an additional back up of all files in image dir using gzip
          (this is *in addition* to the regular backup)
restore - restore image files from the regular backup
          (backups created in 'safe' mode have to be restored manually)\n\n";
}

if (!(-d $basepath)) {
  die $basepath.' is not a directory.';
}

print "Running watermarking program\n";

my $fixed=0;
my $total=0;

if ($command eq 'safe'){
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year+=1900;
  $mon=sprintf "%02d", $mon+1;
  $mday=sprintf "%02d", $mday+1;
  print "\nBacking up all files.\n";
  `tar -cpvzf $backup_dir/backup_images_$year-$mon-$mday-$hour-$min-$sec.tgz $basepath/*`;
}

# Read the base dir for jpg files
opendir THEDIR, "$basepath";
my @allfiles = grep (/\.(jpe?g|png)$/i, sort { uc($a) cmp uc($b) } (readdir THEDIR));
closedir THEDIR;

print "\nWatermarking files in $basepath:\n";

# if commandline argument is restore, restore backed-up files
if ($command eq 'restore'){
  foreach my $file (@allfiles) {
    $total++;
    if ($file =~ /^_/){
      my $restore_file=$file;
      $restore_file=~s/^_//;
      `cp -f $basepath/$file $basepath/$restore_file`;
      `rm -f $basepath/$file`;
      print "Restored file $restore_file\n";
      $fixed++;
    }
  }
# else watermark images
} else {
  foreach my $file (@allfiles) {
    $total++;
    if ($file !~ /^_/){
      print &watermark($basepath, $file, 'horizontal', '0.5,-10', 25);
      $fixed++;
    }
  }
}

print "\nError code ", $? >> 8, ".\n";
print "Went through $total total files. $fixed were not backups.\n";

# Watermarking subroutine
sub watermark {
	my ($basepath, $filename, $orientation, $positions, $transparency) = @_;
	my ($position_x, $position_y) = split(/,/,$positions);
	my ($iw, $is);
	my $percent = $transparency; # transparency

	# set-up
	my $backup_file = "_$filename";
	GD::Image->trueColor(1);
	# open source image
	$is = GD::Image->new("$basepath/$filename") or die("Failed to open \"$filename\"");
	# open watermark image
	$iw = GD::Image->new($watermark_image) or die("Failed to open \"$watermark_image\"");
	# check that we haven't already watermarked this image
	if (-e "$basepath/$backup_file"){
		my $img = GD::Image->new("$basepath/$backup_file") or die("Failed to open \"$backup_file\"");
		if ($img->height == $is->height and $img->width == $is->width){
			return "$filename is already watermarked.\n";
		}
	}
	# check that this image is big enough to be watermarked
	if ($is->width < $min_width or $is->height < $min_height){
		return "$filename is too small to watermark.\n";
	} elsif ($is->width < $iw->width){
		$iw = Image::Resize->new($iw);
		$iw = $iw->resize($is->width,26);
	}
	# adjust parameters
	if ($orientation eq 'vertical') { $iw = $iw->copyRotate270(); }
	if ($position_x < 0){ $position_x = $is->width + $position_x - $iw->width; }
	elsif ($position_x < 1){ $position_x = floor($is->width * $position_x - $iw->width / 2); }
	if ($position_y < 0){ $position_y = $is->height + $position_y - $iw->height; }
	elsif ($position_y < 1){ $position_y = floor($is->height * $position_y - $iw->height / 2); }
	# printf("iw->trueColor() = %d$/", $iw->trueColor());
	# printf("is->trueColor() = %d$/", $is->trueColor());
	# Turn off alpha-blending temporarily for the watermark image.  If
	# we don't do this here, as we adjust each pixel colour and call
	# setPixel(), GD will go through gdAlphaBlend() process for the
	# current pixel colour and what we want to set the colour to.
	$iw->alphaBlending(0);
	# Go through every pixel in the watermark image and adjust the
	# alpha channel value appropriately.
	$percent /= 100.0;
	for (my $h = 0; $h < $iw->height; ++$h) {
		for (my $x = 0; $x < $iw->width; ++$x) {
			my ($px, $alpha);
			# Get pixel's colour value (a.k.a., index)
			$px = $iw->getPixel($x, $h);
			# Get the alpha channel value
			$alpha = ($px >> 24) & 0xff;
			# If it is completely transparent (0x7f = 127) skip
			if ($alpha == 127) { next; }
			$alpha += int((127 - $alpha) * $percent);
			$alpha = 127 if ($alpha > 127); # Cap (paranoia)
			# Adjust the new colour value based on the adjusted
			# alpha channel value and set it.
			$px = ($px & 0x00ffffff) | ($alpha << 24);
			$iw->setPixel($x, $h, $px);
		}
	}
	# Turn on alpha-blending now.
	$iw->alphaBlending(1);
	# copy watermark onto source image
	$is->copy($iw, $position_x, $position_y, 0, 0, $iw->width, $iw->height);

  # back up the file now
	`cp -f $basepath/$filename $basepath/$backup_file`;

  # If there was no error
	if ($? != -1) {
		# open destination/out file for writing
		open(OUT, ">$basepath/$filename") or die("Failed to write \"$filename\": $!");
		binmode OUT;
		# write out resulting image
		if ($filename=~/\.jpe?g$/) { print OUT $is->jpeg(80); }
		elsif ($filename=~/\.png$/) { print OUT $is->png(5); }
		close(OUT);
		return("$filename watermarked successfully!\n");
	} else {
		return("Failed to create backup for $filename.\n");
	}
}
