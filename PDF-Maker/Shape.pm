#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package Shape;

sub top {
	return shift->{Top};
}

sub bottom {
	return shift->{Bottom};
}

sub right {
	return shift->{Right};
}

sub left {
	return shift->{Left};
}

package Rect;

@Rect::ISA = qw(Shape);

%Rect::Anchors = (
	NorthWest	=> 10,	North	=> 11,	NorthEast	=> 12,
	West		=> 20,	Center	=> 21,	East		=> 22,
	SouthWest	=> 30,	South	=> 31,	SouthEast	=> 32,
);

sub new {
	my ( $class, $left, $bottom, $right, $top ) = @_;
	if( ref( $left ) eq $class || ref( $left ) eq 'Poly' ){
		$bottom = $left->bottom( );
		$right = $left->right( );
		$top = $left->top( );
		$left = $left->left( );
	} else {
		$left ||= 0;
		$bottom ||= 0;
		$right ||= $left;
		$top ||= $bottom;
		$left = &PDF::tellSize( $left );
		$right = &PDF::tellSize( $right );
		$bottom = &PDF::tellSize( $bottom );
		$top = &PDF::tellSize( $top );
		if( $right < $left ){
			( $left, $right ) = ( $right, $left );
		}
		if( $top < $bottom ){
			( $top, $bottom ) = ( $bottom, $top );
		}
	}
	bless {
		'Top' => $top,
		'Left' => $left,
		'Right' => $right,
		'Bottom' => $bottom,
		'Width' => $right - $left,
		'Height' => $top - $bottom,
	}, $class;
}

sub height {
	my( $this, $NewHeight ) = @_;
	if( defined $NewHeight ){
		$this->{Height} = &PDF::tellSize( $NewHeight );
		$this->{Top} = $this->{Bottom} + $NewHeight ;
	}
	return $this->{Height};
}

sub width {
	my( $this, $NewWidth ) = @_;
	if( defined $NewWidth ){
		$this->{Width} = &PDF::tellSize( $NewWidth );
		$this->{Right} = $this->{Left} + $NewWidth;
	}
	return $this->{Width};
}

sub topLeft {
	return shift->{Left};
}

sub shrink {
	my( $this, $offset ) = @_;
	$offset = &PDF::tellSize( $offset );
	$this->{Left} += $offset;
	$this->{Right} -= $offset;
	$this->{Top} -= $offset;
	$this->{Bottom} += $offset;
	$this->{Width} -= 2 * $offset;
	$this->{Height} -= 2 * $offset;
	return $this;
}

sub moveBy {
	my( $this, $offx, $offy ) = @_;
	$offx = &PDF::tellSize( $offx );
	$offy = &PDF::tellSize( $offy );
	$this->{Top} += $offy;
	$this->{Left} += $offx;
	$this->{Bottom} += $offy;
	$this->{Right} += $offx;
	return $this;
}

sub getRange {
	my( $this, $y ) = @_;
	return ( $this->{Left}, $this->{Right} );
}

sub union {
	my( $this, $that ) = @_;
	my $left = &PDF::min( $this->{Left}, $that->{Left} );
	my $bottom = &PDF::min( $this->{Bottom}, $that->{Bottom} );
	my $right = &PDF::max( $this->{Right}, $that->{Right} );
	my $top = &PDF::max( $this->{Top}, $that->{Top} );
	return new Rect( $left, $bottom, $right, $top );
}

# Adjust $that according to $width and $height (can be %) and $anchor settings.
sub anchorRect {
	my( $this, $width, $height, $anchor, $that ) = @_;
	my( $w, $h ) = ( $this->{Width}, $this->{Height} );
	if( defined $width ){
		if( $width =~ /([\d\.]+)%/ ){ $width = $1 * $w / 100; }
		$that->width( $width );
	}
	if( defined $height ){
		if( $height =~ /([\d\.]+)%/ ){ $height = $1 * $h / 100; }
		$that->height( $height );
	}
	if( defined $anchor && ( defined $width || defined $height ) ){
		my $v = $Rect::Anchors{$anchor} || 30;
		if( $v % 10 == 1 ){	# North, Center, South
			$that->moveBy( ( $w - $width ) / 2, 0 );
		} elsif( $v % 10 == 2 ){	# NorthEast, East, SouthEast
			$that->moveBy( $w - $width, 0 );
		}
		if( int( $v / 10 ) == 2 ){	# West, Center, East
			$that->moveBy( 0, ( $h - $height ) / 2 );
		} elsif( int( $v / 10 ) == 1 ){	# NorthWest, North, NorthEast
			$that->moveBy( 0, $h - $height );
		}
	}
	return $that;
}

package Poly;

@Poly::ISA = qw(Shape);

sub new {
	my $class= shift;
	my $this = {
		'XVals' => [ ],
		'YVals' => [ ],
		'Slopes' => [ ],
	};
	while( scalar @_ > 1 ){
		push( @{$this->{XVals}}, &PDF::tellSize( shift ) );
		push( @{$this->{YVals}}, &PDF::tellSize( shift ) );
	}
	my $t = scalar( @{$this->{YVals}} );
	my( $i, $j );
	for $i ( 0..$t-1 ){
		$j = ( $i + 1 ) % $t;
		my $tmpx = $this->{XVals}->[$j] - $this->{XVals}->[$i];
		push( @{$this->{Slopes}}, abs( $tmpx ) < 1e-6? 'Inf':
			( $this->{YVals}->[$j] - $this->{YVals}->[$i] ) / $tmpx );
	}
	my @tmpys = sort{ $a <=> $b } @{$this->{YVals}};
	$this->{Top} = $tmpys[-1];
	$this->{Bottom} = $tmpys[0];
	my @tmpxs = sort{ $a <=> $b } @{$this->{XVals}};
	$this->{Left} = $tmpxs[0];
	$this->{Right} = $tmpxs[-1];
	bless $this, $class;
	return $this;
}

sub topLeft {
	my $this = shift;
	my @xs = $this->getRange( $this->{Top} );
	return $xs[0];
}

sub getPoints {
	my $this = shift;
	my @coords = ( );
	for( 1 .. scalar @{$this->{YVals}} ){
		push( @coords, $this->{XVals}->[$_-1], $this->{YVals}->[$_-1] );
	}
	push( @coords, @coords[0..1] );
	return @coords;
}

sub getRange {
	my( $this, $y ) = @_;
	my $t = scalar @{$this->{YVals}};
	my( $i, $j );
	my @xs = ( );
	for $i ( 0..$t-1 ){
		$j = ( $i + 1 ) % $t;
		# Note: A line segment has two connection points; the starting point is included in the segment while the ending point is not.
#		print $i . " -t " . $t . " -y " . $y . " -YVi " . $this->{YVals}->[$i] . " -YVj " . $this->{YVals}->[$j] . " -Slope " . $this->{Slopes}->[$i] . " -XVi " . $this->{XVals}->[$i] . "<br>";
		next unless( $y < $this->{YVals}->[$i] && $y >= $this->{YVals}->[$j] || $y > $this->{YVals}->[$i] && $y <= $this->{YVals}->[$j] );
		if( $this->{Slopes}->[$i] ne 'Inf' ){
#			print "( " . $y . " - " . $this->{YVals}->[$i] ." ) / " . $this->{Slopes}->[$i] . " + " . $this->{XVals}->[$i] . "<br>";
			push( @xs, ( $y - $this->{YVals}->[$i] ) / $this->{Slopes}->[$i] + $this->{XVals}->[$i] ) if( $this->{Slopes}->[$i] );
		} else {
			push( @xs, $this->{XVals}->[$i] );
		}
	}
#	print "return<br>";
	if( @xs > 1 ){
		return sort { $a <=> $b } @xs;
	} else {
		return ( $this->{Left}, $this->{Right} );
	}
}

1;
