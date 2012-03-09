#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package PDFDocEncoding;

use PDFTreeNode;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $base, $diffs ) = @_;
	my $this = {
		'Base' => ( $base || 'StandardEncoding' ),
		'Diffs' => $diffs,	# Hash ref, key is char code, value is array ref, array contains standard names
	};
	bless $this, $class;
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Type /Encoding',
		'/Differences [ ',
	);
	for( sort { $a <=> $b } keys %{$this->{Diffs}} ){
		print $PDF::endln . join( ' ', $_, map { '/' . $_ } @{$this->{Diffs}->{$_}} );
	}
	print join( $PDF::endln,
		'',
		' ]',
		'>> ',
		'endobj',
		''
	);
}

package AcroForm;

use PDFTreeNode;

@ISA = qw(PDFTreeNode);
%AcroForm::Themes = map { $_ => 1 } qw(Default WinXP);

sub new {
	my( $class, $url, $attr ) = @_;
	my $this = {
		'Fields' => [ ],
		'Url' => $url,
		'DefaultFont' => undef,
		'UsedFonts' => { },
		'PDFDocEncoding' => new PDFDocEncoding( 'StandardEncoding', { 24 => [ @PDFFont::PDFDocEncodingExtra ], 127 => [ @PDFFont::PDFDocEncoding ] } ),
		'ImportedFields' => [ ],	# v3.0
		'Theme'	=> 'Default',	# v3.0; currently only 'Default' and 'WinXP' are defined.
		'NeedAppearance' => 0,	# v3.0
		'DefinedFieldNames' => { },	# v3.0; key: field name; value: 1
	};
	bless $this, $class;
	if( exists $attr->{Theme} && exists $AcroForm::Themes{ $attr->{Theme} } ){
		$this->{Theme} = $attr->{Theme};
	}
	$PDF::root->getCatalog( )->appendAcroForm( $this );
	$this->appendChild( $this->{PDFDocEncoding} );
#	$this->{UsedFonts}->{ $this->{DefaultFont}->getName( ) } = 1;
	for( keys %PDFFont::AdobeFontNames ){
		my $font = $PDF::root->getFont( $_, 'PDFDocEncoding' );
		$this->{UsedFonts}->{ $font->getName( ) } = 1;
	}
	$this->{DefaultFont} = $PDF::root->getFont( ( defined $PDFFont::AdobeFontNames{ $attr->{FontFace} }? $attr->{FontFace}: 'Times-Roman' ), 'PDFDocEncoding' );
	return $this;
}

sub appendField {
	my( $this, $oField ) = @_;
	if( !$oField->{par} ){
		push( @{$this->{Fields}}, $oField );
		$this->appendChild( $oField );
		$this->{DefinedFieldNames}->{ $oField->{Name} } = 1;
	}
	return $oField;
}

sub appendImportedField {
	my( $this, $pobj, $prefix, $forcena ) = @_;	# $prefix is the prefix to field names in case there's collision
	push( @{$this->{ImportedFields}}, $pobj );
	if( exists $pobj->{Data}->{T} ){
		my $n = $pobj->{Data}->{T}->getStr( );
		if( defined $prefix && length( $prefix ) > 0 && exists $this->{DefinedFieldNames}->{ $n } ){
			$pobj->{Data}->{T}->setStr( $n = "$prefix.$n" );
		}
		$this->{DefinedFieldNames}->{ $n } = 1;
	}
	if( $forcena || !exists $pobj->{Data}->{AP} ){
		$this->{NeedAppearance} = 1;
	}
	return $pobj;
}

sub setEncoding {
	my( $this, $pdict ) = @_;	# $pdict is the Encoding data as PDict
	return if( !exists $pdict->{Differences} );
	my $array = $pdict->{Differences};
	my $diff = { };
	my $p;
	for( @$array ){
		if( ref( $_ ) eq 'PNumber' ){
			$p = $diff->{ $_->[0] } = [ ];
		} else {	# Then it must be PName
			push( @$p, $_->[0] );
		}
	}
	$this->deleteChild( $this->{PDFDocEncoding} );
	$this->{PDFDocEncoding} = new PDFDocEncoding( 'StandardEncoding', $diff );
	$this->appendChild( $this->{PDFDocEncoding} );
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Fields [ ' . join( ' ', map{ "$_->{ObjId} 0 R" } ( @{$this->{Fields}}, @{$this->{ImportedFields}} ) ) . ' ] ',
		qq{/DR << /Font << },
		( map{ sprintf( "/%s %i 0 R ", $_, $PDF::root->getObjByName( $_ )->{ObjId} ) } keys %{$this->{UsedFonts}} ),
		'>> ',
		qq{/Encoding << /PDFDocEncoding $this->{PDFDocEncoding}->{ObjId} 0 R >> },
		'>> ',
	);
	if( $this->{NeedAppearance} ){
		print "$PDF::endln/NeedAppearances true";
	}
	print join( $PDF::endln,
		'',
		'>> ',
		'endobj',
		''
	);
}

sub startXML {
	my( $this, $dep ) = @_;
	print "\t" x ( $dep + 1 ), '<Form',
		' Url="', &PDF::escXMLChar( $this->{Url} ), '"',
		' FontFace="', $this->{DefaultFont}->{FontPtr}->{BaseFont}, '"',
		' Theme="', $this->{Theme}, '"',
		" >\n";
}

sub endXML {
	my( $this, $dep ) = @_;
	print "\t" x ( $dep + 1 ), "</Form>\n";
}

sub newFromXML {
	my( $class, $xml ) = @_;
	return new AcroForm( $xml->{Url}, { 'FontFace' => $xml->{FontFace}, 'Theme' => $xml->{Theme} } );
}

sub finalize {
	my $this = shift;
	@{$this->{Fields}} = ( );
	delete $this->{DefaultFont};
	@{$this->{ImportedFields}} = ( );
}

1;
