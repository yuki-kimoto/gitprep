package Gitprep::Image;

my $dimension = 5;      # Generated identicon square side size: keep it odd.

sub HSLtoRGB {
  my ($self, $h, $s, $l) = @_;

  # Convert a HSL colorspace color into RGB.
  $s /= 100.0;
  $l /= 100.0;
  return [0, 0, 0] unless $s;
  my $sextant = $h / 60.0;
  my $c = (1.0 - abs(2.0 * $l - 1.0)) * $s;
  my $x = (1.0 - abs($sextant % 2.0 - 1.0)) * $c;
  my $m = $l - $c / 2.0;
  my $i = int($sextant);
  my @r = ($c, $x, 0.0, 0.0, $x, $c);
  my @g = ($x, $c, $c, $x, 0.0, 0.0);
  my @b = (0.0, 0.0, $x, $c, $c, $x);
  return [
    int(($r[$i] + $m) * 255.0),
    int(($g[$i] + $m) * 255.0),
    int(($b[$i] + $m) * 255.0)
  ];
}

sub raster2paths {
  my ($self, $width, $height, $pixel, $xoffset, $yoffset) = @_;

  # Convert a monochrome pixelized image into SVG-like paths.
  # $pixel is a subroutine to get the image pixel at <x, y>.
  # Offsets are added to final absolute coordinates.
  $xoffset ||= 0;
  $yoffset ||= 0;

  my $segments = {};

  local *do_one_row = sub {
    my ($y, $prev_row, $pixel) = @_;

    # Find horizontal and vertical edge segments in the raster image and
    # enters the in the segments table.

    local *enter_edge = sub {
      my ($x0, $y0, $x1, $y1, $forward, $direction) = @_;

      # Enter a segment in the table.
      # Always keep the non-zero pixels on the right side of the edge.
      ($x0, $y0, $x1, $y1) = ($x1, $y1, $x0, $y0) unless $forward;
      $direction <<= 2 unless $forward;
      # Direction is now a bitmask:
      # - xxx1 if there is a down edge starting at <x0, y0>
      # - xx1x if there is a right edge starting at <x0, y0>
      # - x1xx if there is an up edge starting at <x0, y0>
      # - 1xxx if there is a left edge starting at <x0, y0>
      my $edges = $segments->{"$x0,$y0"} || 0;
      $segments->{"$x0,$y0"} = $edges | $direction;
    };

    my @current_row;
    my $prev_col = 0;
    # Detect all vertical edges on row y and all horizontal edges above it
    # using the previous row data.
    for my $x (0 .. $width - 1) {
      my $p = $pixel->($x, $y);
      push @current_row, $p;
      enter_edge($x, $y, $x, $y + 1, $p, 0x1) if $p != $prev_col;
      enter_edge($x, $y, $x + 1, $y, !$p, 0x2) if $p != $prev_row->[$x];
      $prev_col = $p;
    }
    # Detect trailing vertical edge.
    enter_edge($width, $y, $width, $y + 1, 0, 0x1) if $prev_col;

    return \@current_row;   # For use when processing next row.
  };

  # Enter unit edges in table. Edge direction always keeps non-zero pixels on
  # their right side.
  my $prev_row = [(0) x $width];
  for my $y (0 .. $height - 1) {
    $prev_row = do_one_row($y, $prev_row, $pixel);
  }
  do_one_row($height, $prev_row, sub { return 0; });

  # Merge detected edges into longest path segments as possible.
  my @paths;
  foreach my $start (keys %$segments) {
    my ($startx, $starty) = split ',', $start;
    # Generate all paths starting at <startx, starty>.
    while (my $edges = $segments->{$start}) {
      # Start a new path.
      my $index = $start;
      my ($x, $y) = ($startx, $starty);
      my $stroke = 0;           # Number of units in the same direction.
      my $direction = 0;        # Current direction.
      my $moves = [];
      while ($edges = $segments->{$index}) {
        if (!($edges & $direction)) {
          # No more edge in the current direction. Save current move and
          # start a new one.
          push @$moves, [$direction, $stroke] if $stroke;
          $stroke = 0;
          $direction = (~$edges + 1) & $edges;	# Least significant bit set.
        }
        # Compute next coordinates according to direction.
        $y += 1 if $direction == 0x1;
        $x += 1 if $direction == 0x2;
        $y -= 1 if $direction == 0x4;
        $x -= 1 if $direction == 0x8;
        $stroke++;
        $segments->{$index} &= ~$direction;     # Remove edge from segment table
        $index = "$x,$y";
      }
      push @$moves, [$direction, $stroke] if $stroke;   # Save last move.

      # At this point, all moves should have formed a closed path.
      if ($x != $startx || $y != $starty) {
        printf "Warning: Unclosed path <%u, %u> -- <%u, %u>\n",
               $startx, $starty, $x, $y;
      }

      # Combine all moves into a path.
      my ($xs, $ys) = ($startx + $xoffset, $starty + $yoffset);
      my @p = ['M', "$xs $ys"];
      push @p, [($_->[0] & 0x5)? 'v': 'h', ($_->[0] & 0xc)? -$_->[1]: $_->[1]] for (@$moves);
      push @paths, \@p;
    }
  }

  return \@paths;
}

sub identicon {
  my ($self, $name) = @_;

  # Generate an SVG identicon image from the given name.

  # Fingerprint
  require Crypt::Digest::SHA256;
  my $fingerprint = Crypt::Digest::SHA256::sha256($name);
  my @nibbles = map hex($_),
    (unpack('H' x 32, $fingerprint), (unpack 'h' x 32, $fingerprint));
  my @parity = (0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0);

  # Pixel color
  my $h = pop(@nibbles) * 360 / 16;
  my $colors = $self->HSLtoRGB($h, 45, 69);
  my $color = (($colors->[0] * 256) + $colors->[1]) * 256 + $colors->[2];

  my $hpix = ($dimension + 1) / 2;

  # Populate raster with tainted pixels
  my @raster;
  for (my $y = $dimension; $y--;) {
    my @row;
    for (my $x = ($dimension + 1) / 2; $x--;) {
      $row[$x] = $parity[pop @nibbles];
    }
    push @row, reverse @row[0 .. @row - 2];
    $raster[$y] = \@row;
  }

  # Convert to paths.
  my $paths = $self->raster2paths($dimension, $dimension, sub {
    my ($x, $y) = @_;
    return $raster[$y][$x];
  }, 0.5, 0.5);

  # Generate the SVG.
  my @path;
  foreach (@$paths) {
    foreach  (@$_) {
      my ($cmd, $args) = @$_;
      push @path, "$cmd$args";
    }
  }
  my $d = $dimension + 1;
  my $clr = sprintf "%06x", $color;
  my $svg = '<svg xmlns="http://www.w3.org/2000/svg"';
  $svg .= " viewBox=\"0 0 $d $d\">\n";
  $svg .= "  <path style=\"fill: #$clr; fill-opacity: 1;\"\n";
  $svg .= "    d=\"" . join(' ', @path) . "\" />\n";
  $svg .= "</svg>\n";
  return $svg;
}

sub get_avatar_png {
  my ($self, $data) = @_;
  require Imager;
  my $img = Imager->new(data => $data);
  return $img unless $img;
  my $width = $img->getwidth;
  my $height = $img->getheight;
  return undef unless $width && $height;

  # Crop to make it square.
  my $size = $width;
  if ($width != $height) {
    $size = $height unless $width < $height;
    my $xcrop = ($width - $size) / 2;
    my $ycrop = ($height - $size) / 2;
    $img = $img->crop(left => $xcrop, right => $size + $xcrop,
      top => $ycrop, $bottom => $size + $ycrop);
  }

  # Scale down if larger than 320x320.
  if ($size > 320) {
    $size = 320;
    $img = $img->scale(xpixels => $size, ypixels => $size);
  }

  # Retrieve PNG image data.
  my $buffer;
  $img->write(data => \$buffer, type => 'png');

  return ($buffer, $size);
}

sub image_formats {
  require Imager;
  return Imager->read_types;
}
  
1;
