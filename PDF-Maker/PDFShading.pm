#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package PDFShading;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $type, $attr ) = @_;
	$type ||= 'Linear';
	my $this = {
		'ShadingType' => ( { 'Axial'=>2, 'Linear'=>2, 'Radial'=>3 }->{ $type } || 2 ),
		'ColorSpace' => ( $attr->{ColorSpace} || $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ),
		'Coords' => [ ],
		'FromColor' => ( $attr->{FromColor} || 'White' ),
		'ToColor' => ( $attr->{ToColor} || 'Blue' ),
		'Function' => undef,
		'Centered' => ( $attr->{Centered} || 0 ),
	};
	bless $this, $class;
	$PDF::root->getCatalog( )->getPagesRoot( )->appendShading( $this );
	$this->setName( $attr->{Name} );
	$this->{Function} = join( ' ',
		'<<',
		'/FunctionType 2',
		'/Domain [0 1]',
		'/C0 [' . join( ' ', &Color::tellColor( $this->{FromColor}, $this->{ColorSpace} ) ) . ']',
		'/C1 [' . join( ' ', &Color::tellColor( $this->{ToColor}, $this->{ColorSpace} ) ) . ']',
		'/N 1',		# Always linear interpolation
		'>>',
	);
	$this->{ShadingType} ||= 2;
	if( $this->{ShadingType} == 2 ){
		#Valid values for Dir: 'L->R', 'R->L', 'T->B', 'B->T', 'TL->BR', 'TR->BL', 'BR->TL', 'BL->TR'
		push( @{$this->{Coords}}, 0, 0, 0, 0 );
		if( defined $attr->{Dir} && $attr->{Dir} =~ m/(\w+)->(\w+)/ ){
			my( $f, $t ) = ( $1, $2 );
			$f =~ /R$/i && do { $this->{Coords}->[0] = 1; };
			$f =~ /^T/i && do { $this->{Coords}->[1] = 1; };
			$t =~ /R$/i && do { $this->{Coords}->[2] = 1; };
			$t =~ /^T/i && do { $this->{Coords}->[3] = 1; };
		} elsif( defined $attr->{Coords} ){
			splice( @{$this->{Coords}}, 0, 4, @{$attr->{Coords}} );
		} else {
			$this->{Coords}->[3] = 1;
		}
	} elsif( $this->{ShadingType} == 3 ){
		if( defined $attr->{Dir} && $attr->{Dir} =~ m/(\w+)->(\w+)/ ){
			my %coords = (
				'L->R'		=> [ 0.0, 0.5, 0.0, 0.0, 0.5, 1.0 ],
				'R->L'		=> [ 1.0, 0.5, 0.0, 1.0, 0.5, 1.0 ],
				'T->B'		=> [ 0.5, 1.0, 0.0, 0.5, 1.0, 1.0 ],
				'B->T'		=> [ 0.5, 0.0, 0.0, 0.5, 0.0, 1.0 ],
				'TL->BR'	=> [ 0.0, 1.0, 0.0, 0.0, 1.0, 1.414 ],
				'BR->TL'	=> [ 1.0, 0.0, 0.0, 1.0, 0.0, 1.414 ],
				'TR->BL'	=> [ 1.0, 1.0, 0.0, 1.0, 1.0, 1.414 ],
				'BL->TR'	=> [ 0.0, 0.0, 0.0, 0.0, 0.0, 1.414 ],
			);
			my $coords = ( $coords{ $attr->{Dir} } || [ 0.5, 0.5, 0, 0.5, 0.5, 0.5 ] );
			push( @{$this->{Coords}}, @$coords );
		} elsif( defined $attr->{Coords} ){
			push( @{$this->{Coords}}, @{$attr->{Coords}} );
		} else {
			push( @{$this->{Coords}}, 0.5, 0.5, 0, 0.5, 0.5, 0.707 );
		}
	}
	if( $attr->{Centered} ){
		$this->{Function} = join( $PDF::endln,
			'<<',
			'/FunctionType 3',
			'/Domain [0 1]',
			'/Functions [',
			$this->{Function},
			$this->{Function},
			']',
			'/Bounds [' . ( $attr->{Bound} || 0.5 ). ']',
			'/Encode [1 0 0 1]',
			'>>',
		);
	}
	return $this;
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<<',
		qq{/ShadingType $this->{ShadingType}},
		qq{/ColorSpace /Device$this->{ColorSpace}},
		'/Coords [' . join( ' ', @{$this->{Coords}} ) . ']',
		'/Extend [true true]',
		qq{/Function $this->{Function}},
		'>>',
		'endobj',
		'',
	);
}

sub startXML {
	my( $this, $dep ) = @_;
	print "\t" x $dep, sprintf( qq{<Shading Type="%s"}, [ '', '', 'Linear', 'Radial' ]->[ $this->{ShadingType} ] );
	for( qw(Name Centered FromColor ToColor ColorSpace) ){
		next unless defined $this->{$_};
		print qq{ $_="$this->{$_}"};
	}
	print ' Coords="', join( ', ', @{$this->{Coords}} ), '" />', "\n";
}

sub newFromXML {
	my( $class, $xml ) = @_;
	bless $xml, 'HASH';
	if( defined $xml->{Coords} ){
		my @coords = split( /,\s+/, $xml->{Coords} );
		$xml->{Coords} = [ @coords ];
	}
	return new PDFShading( $xml->{Type}, $xml );
}

1;
