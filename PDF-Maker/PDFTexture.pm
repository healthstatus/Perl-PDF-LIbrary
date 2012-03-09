#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package ColorSpace;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $type, $attr ) = @_;
	my $this = {
		'Type' => $type,
		'Base' => ( $attr->{Base} || $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ),
	};
	bless $this, $class;
	$this->setName( $attr->{Name} );
	$PDF::root->getCatalog( )->getPagesRoot( )->add( $this );
	return $this;
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		qq{[/$this->{Type} /Device$this->{Base}]},
		'endobj',
		'',
	);
}

############################################################################

package PDFTexture;

use ImageContent;
use GraphContent;

@ISA = qw(PDFStream);

# These magic values are bitmap data for the small 8x8 images used as a pattern.
%PDFTexture::BitMaps = (
	'brick'		=> '0101FF101010FF01',
	'bricktilt'	=> '3020408001028448',
	'buttons'	=> '558239B8398041AA',
	'cargonet'	=> '87CEEC781E3773E1',
	'checker'	=> 'CCCC3333CCCC3333',
	'circuits'	=> 'ADD67BBD6BD6BD7B',
	'daisies'	=> 'E173270240E49E87',
	'darklineh'	=> 'FFFF0000FFFF0000',
	'darklinev'	=> '6666666666666666',
	'darktiltl'	=> '381C0E0783C1E070',
	'darktiltr'	=> 'E0C183070E1C3870',
	'dizzy'		=> 'C1F81EF8C18F3C8F',
	'fence'		=> 'A9A659659A6A9556',
	'grid'		=> 'EFEFFF38FFEFEFEF',
	'key'		=> '01FD0575455D417F',
	'medlineh'	=> '00FF00FF00FF00FF',
	'medlinev'	=> 'CCCCCCCCCCCCCCCC',
	'medtiltl'	=> '663399CC663399CC',
	'medtiltr'	=> '3366CC993366CC99',
	'round'		=> '286CD728D76C2928',
	'scales'	=> '1ED5DA6DAA67C108',
	'square'	=> '007E424242427E00',
	'stars'		=> '0008087F182C2400',
	'stone'		=> '51B21000F7B231B2',
	'thatches'	=> '078BDDB870B8DD8E',
	'thinlineh'	=> '000000FF000000FF',
	'thinlinev'	=> '4444444444444444',
	'thintiltl'	=> '1188442211884422',
	'thintiltr'	=> '4488112244881122',
	'tile'		=> 'BA7DFEFFFE7DBA55',
	'triangle'	=> '78F8F9FBFF081838',
	'waffle'	=> 'B265F7BB1065B265',
	'wave'		=> '4884033048840330',
	'wiretilt'	=> '1010F10101011F10',
	'heart'		=> '0044AA9292442810',
	'mesh'		=> 'C381183C3C1881C3',
);

sub new {
	my( $class, $param, $attr ) = @_;
	my $this = new PDFStream;
	my $newattr = {
		'Image' => undef,
		'Code' => undef,
		'PaintType' => 1,
		'Stream' => undef,
		'Width' => 8,
		'Height' => 8,
		'XSpacing' => $attr->{XSpacing} || 0,
		'YSpacing' => $attr->{YSpacing} || 0,
		'Type' => $param,
		'XObject' => [ ],
		'XML' => [ ],
		'Resources' => new Resources( ),
	};
	for( keys %$newattr ){
		$this->{$_} = $newattr->{$_};
	}
	bless $this, $class;
	$this->setName( ref( $attr ) eq 'HASH'? $attr->{Name}: '' );
	$PDF::root->getCatalog( )->getPagesRoot( )->appendPattern( $this );
	if( ( !$param || !defined $PDFTexture::BitMaps{lc($param)} ) && ref( $param ) ne 'ImageContent' && ref( $param ) ne 'GraphContent' ){
		if( defined $attr->{Image} ){
			$param = ( ref( $attr->{Image} ) eq 'ImageContent'? $attr->{Image}: new ImageContent( $attr->{Image} ) );	# ImageContent object or file name
		} elsif( defined $attr->{Graph} && ref( $attr->{Graph} ) eq 'GraphContent' ){
			$param = $attr->{Graph};
		} else {
			$param = 'brick';
		}
	}
	if( ref( $param ) eq 'ImageContent' ){
		push( @{$this->{XML}}, qq{Image="$param->{Name}"} );
		$this->{Image} = $param;
		$this->{Width} = $param->{DisplayWidth} unless defined $attr->{Width};
		$this->{Height} = $param->{DisplayHeight} unless defined $attr->{Height};
		$this->{Resources}->{XObject}->{ $param->{Name} } = 1;
	} elsif( ref( $param ) eq 'GraphContent' ){
		$this->{Width} = $attr->{Width} || $param->{Container}->{Width};
		$this->{Height} = $attr->{Height} || $param->{Container}->{Height};
		push( @{$this->{XML}}, qq{Width="$this->{Width}"} ) unless defined $attr->{Width};
		push( @{$this->{XML}}, qq{Height="$this->{Height}"} ) unless defined $attr->{Height};
		if( $attr->{Uncolored} ){
			$this->{PaintType} = 2;
			$this->{ColorSpace} = new ColorSpace( 'Pattern', { 'Base'=> ( $attr->{ColorSpace} || 'RGB' ) } );
			push( @{$this->{XML}}, qq{Uncolored="1"} );
			push( @{$this->{XML}}, qq{ColorSpace="$this->{ColorSpace}->{Base}"} );
			$this->{Resources}->{ColorSpace}->{ $this->{ColorSpace}->{Name} } = 1;
		}
		for my $res ( keys %{$param->{Resources}} ){
			for( keys %{$param->{Resources}->{$res}} ){
				$this->{Resources}->{$res}->{$_} = 1;
			}
		}
	} else {
		my( @colors ) = ( );
		push( @{$this->{XML}}, qq{FgColor="$attr->{FgColor}"} );
		push( @{$this->{XML}}, qq{BgColor="$attr->{BgColor}"} );
		push( @colors, &Color::tellColor( ( $attr->{FgColor} || 'Black' ), 'RGB' ) );
		push( @colors, &Color::tellColor( ( $attr->{BgColor} || 'White' ), 'RGB' ) );
		$this->{Image} = new ImageContent( new PDFStream( pack( 'H*', ( $PDFTexture::BitMaps{lc($param)} || '0042241818244200' ) ), { 'InternalUse' => 1 } ),
			$this->{Width}, $this->{Height}, { 'BitsPerComponent'=>1, 'Type'=>'Indexed', 'Inline'=> 1,
			'ColorTable'=> join( '', map{ chr( int( $_ * 255 ) ) } @colors ) } );
		push( @{$this->{XML}}, qq{Type="$this->{Type}"} );
	}
	if( $attr->{Scale} ){
		push( @{$this->{XML}}, qq{Scale="$attr->{Scale}"} );
		$this->{Width} *= $attr->{Scale};
		$this->{Height} *= $attr->{Scale};
	} else {
		if( $attr->{Width} ){
			$this->{Width} = &PDF::tellSize( $attr->{Width} );
			push( @{$this->{XML}}, qq{Width="$attr->{Width}"} );
		}
		if( $attr->{Height} ){
			$this->{Height} = &PDF::tellSize( $attr->{Height} );
			push( @{$this->{XML}}, qq{Height="$attr->{Height}"} );
		}
	}
	if( ref( $param ) eq 'ImageContent' ){
		$this->{Stream} = sprintf( "%.4f 0 0 %.4f 0 0 cm /%s Do", $this->{Width}, $this->{Height}, $this->{Image}->{Name} );
		push( @{$this->{XObject}}, $this->{Image} );
	} elsif( ref( $param ) eq 'GraphContent' ){
		$this->{Stream} = $param->{Stream};
		push( @{$this->{XObject}}, @{$param->{XObject}} );
	} else {
		$this->{Stream} .= join( ' ', 'q', $this->{Width}, 0, 0, $this->{Height}, 0, 0, 'cm',
			$this->{Image}->makeInlineCode( ), 'Q', $PDF::endln );
	}
	for( qw(XSpacing YSpacing Rotation SkewX SkewY) ){
		if( defined $attr->{$_} ){ push( @{$this->{XML}}, qq{$_="$attr->{$_}"} ); }
	}
	my $cosval = defined $attr->{Rotation}? cos( $attr->{Rotation} * 3.1416 / 180 ): 1;
	my $sinval = defined $attr->{Rotation}? sin( $attr->{Rotation} * 3.1416 / 180 ): 0;
	my $alpha = defined $attr->{SkewY}? sin( $attr->{SkewY} * 3.1416 / 180 ) / cos( $attr->{SkewY} * 3.1416 / 180 ): 0;
	my $beta = defined $attr->{SkewX}? sin( $attr->{SkewX} * 3.1416 / 180 ) / cos( $attr->{SkewX} * 3.1416 / 180 ): 0;
	$this->{Matrix} = sprintf( "%.4f %.4f %.4f %.4f 1 1",
		$cosval - $sinval * $alpha, $sinval + $cosval * $alpha, $cosval * $beta - $sinval, $sinval * $beta + $cosval );
	return $this;
}

sub dup {
	my( $this ) = @_;
	return new PDFTexture( $this->{Type} );
}

sub customCode {
	my $this = shift;
	#  Content stream is typically very short, so no compression is needed.
	print join( $PDF::endln,
		'',
		'/Type /Pattern',
		'/PatternType 1',
		qq{/PaintType $this->{PaintType}},
		'/TilingType 1',
		'/XStep ' . ( $this->{Width} + $this->{XSpacing} ),
		'/YStep ' . ( $this->{Height} + $this->{YSpacing} ),
		qq{/BBox [ 0 0 $this->{Width} $this->{Height} ]},
		'/Length ' . ( length $this->{Stream} ),
		qq{/Matrix [ $this->{Matrix} ]},
		'/Resources <<',
		'/ProcSet [ /PDF /Text /ImageC /ImageI ] ',
		'',
	);
	for my $res ( keys %{$this->{Resources}} ){
		next unless( keys %{$this->{Resources}->{$res}} );
		print "/$res <<";
		map { printf( "/%s %d 0 R ", $_, &PDF::getObjByName( $_ )->{ObjId} ); } keys %{$this->{Resources}->{$res}};
		print ">>$PDF::endln";
	}
	print qq{>>$PDF::endln};
}

sub startXML {
	my( $this, $dep ) = @_;
	print "\t" x $dep, qq{<Texture Name="$this->{Name}" }, join( ' ', @{$this->{XML}} );
	if( ref( $this->{Type} ) eq 'GraphContent' ){
		print ">\n";
		for( @{$this->{Type}->{XML}} ){
			print "\t" x ( $dep + 1 ), $_, "\n";
		}
	} else {
		print " />\n";
	}
}

sub endXML {
	my( $this, $dep ) = @_;
	if( ref( $this->{Type} ) eq 'GraphContent' ){
		print "\t" x $dep, "</Texture>\n";
	}
}

sub newFromXML {
	my( $class, $xml ) = @_;
	bless $xml, 'HASH';
	if( defined $xml->{Image} ){
		return new PDFTexture( &PDF::getObjByName( $xml->{Image} ), $xml );
	} elsif( defined $xml->{Type} ){
		return new PDFTexture( $xml->{Type}, $xml );
	} else {
		$xml->{InternalUse} = 1;
		$xml->{Rect} = new Rect( 0, 0, $xml->{Width}, $xml->{Height} );
		return new PDFTexture( GraphContent->newFromXML( $xml ), $xml );
	}
}

sub finalize {
	my $this = shift;
	undef $this->{Resources};
	@{$this->{XObject}} = ( );
	@{$this->{XML}} = ( );
}

1;
