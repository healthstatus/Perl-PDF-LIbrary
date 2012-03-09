#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package Page;

@Page::ISA = qw(PDFTreeNode);

use strict;
use Shape;
use Outlines;
use XML::Parser;
use GraphContent;
use Carp;

@Page::TransTypes = qw(NONE Split Blinds Box Wipe Dissolve Glitter R);

sub new {
	my( $class, $attr ) = @_;
	my $rotation = 0;
	if( ref( $attr ) eq 'HASH' ){
		$rotation = $attr->{Rotation} || 0;
		$rotation %= 4;
	}
	my $this = {
		'Contents' => [ ],
		'Annots' => [ ],
		'Trans' => 0,
		'Duration' => 0,
		'TransDur' => 0,
		'Direction' => 0,
		'Dimension' => 'H',
		'MediaBox' => [ 0, 0 ],	# Guaranteed to have 4 elements before construtor returns
		'CropBox' => [ ],	# New in v2.6
		'ArtBox' => [ ],	# New in v3.0
		'Motion' => 'O',	# Must be 0, 90 (Wipe only), 180 (Wipe only), 270, or 315 (Glitter only)
		'Rotation' => $rotation,	# 0: Normal, 1: 90 degree counterclockwise; 2: 90 degree clockwise; 3: upside-down
		'Name' => '',
		'TplObjNames' => [ ],
		'InternalUse' => ( ref $attr && defined( $attr->{InternalUse} ) && $attr->{InternalUse}? 1: 0 ),	# V2.6 for Form XObject
		'PObject' => 0,			# New in v3.0; PObject as an imported page
		'PObjectArray'	=> undef,
		'SkipAnnots' => 0,	# Skip annotations when importing from a PDFFile page?
		'ExportedNames' => { },	# New in v3.0; names exported to resource dictionaries of imported pages
		'AlwaysOnTop' => 0,	# New in v3.0, used by imported page object
		'Graphics' => 0,	# A default GraphContent layer for the page, v3.0
		'RenamedResources' => { },
	};
	bless $this, $class;
	# Now normalize all allowed initiation methods into a single one: hash reference.
	if( ref( $attr ) eq 'Rect' ){	# Rect defining page size
		my $rect = new Rect( $attr );
		$attr = { 'Box' => $rect };
	} elsif( ref( $attr ) eq 'HASH' ){	# Attribute
		if( exists $attr->{Size} ){
			$this->{Size} = $attr->{Size};
			my $size = defined $Pages::PageSizes{$attr->{Size}}? $Pages::PageSizes{$attr->{Size}}: $Pages::PageSizes{Letter};
			$attr->{Box} = new Rect( 0, 0, $size->[0], $size->[1] );
		}
	} elsif( defined $attr && exists $Pages::PageSizes{$attr} ){	# Page size name
		$attr = { 'Box' => new Rect( 0, 0, @{$Pages::PageSizes{$attr}} ) };
	} else {
		$attr = { };
	}
	$this->setName( $attr->{Name} || '' );
	if( exists $attr->{Box} && ref( $attr->{Box} ) eq 'Rect' ){
		push( @{$this->{MediaBox}}, $attr->{Box}->width( ), $attr->{Box}->height( ) );
	} elsif( exists $attr->{Width} && exists $attr->{Height} ){
		push( @{$this->{MediaBox}}, PDF::tellSize( $attr->{Width} ), PDF::tellSize( $attr->{Height} ) );
	} else {
		push( @{$this->{MediaBox}}, @{$PDF::root->{Catalog}->{Pages}->{MediaBox}}[2..3] );
	}
	unless( $this->{InternalUse} ){	# Form XObject doesn't count as a page
		$PDF::root->getPagesRoot( )->appendPage( $this );
		$PDF::root->setCurrPage( $this );
		if( $attr->{Trans} ){
			for( qw(Trans TransDur Direction Dimension Motion) ){
				$this->{$_} = $attr->{$_};
			}
		}
		if( $attr->{Duration} ){
			$this->{Duration} = $attr->{Duration};
		}
		if( exists $attr->{Bookmark} ){
			new Outlines( $attr->{Bookmark}, { 'Name' => ( defined $attr->{BkName}? $attr->{BkName}: undef ) } );
		}
	}
	# Import one page from an existing PDF file.
	if( exists $attr->{ImportSource} && ref( $attr->{ImportSource} ) eq 'PDFFile' ){
		if( $attr->{ImportSource}->getEncryptState( ) ){
			croak "Can't import from an encrypted PDF file";
		}
		$PDF::root->{ImportedFiles}->{ $attr->{ImportSource}->{FileName} } ||= { };
		$this->{ImportSource} = $attr->{ImportSource}->{FileName};
		$this->{ImportPage} = $attr->{ImportPage};
		my $pageobjs;
		if( $attr->{SkipAnnots} ){
			$this->{SkipAnnots} = 1;
			$PDF::SkippedValues->{Page}->{Annots} = 1;
		}
		( $pageobjs, $this->{PObjectArray} ) = $attr->{ImportSource}->copyPages( $PDF::root->{ImportedFiles}->{ $attr->{ImportSource}->{FileName} }, $attr->{ImportPage} );
		delete $PDF::SkippedValues->{Page}->{Annots};
		# $this->{PObject} is the PObject for the page;
		# $this->{PObjectArray} is an array of all PObjects required for this page.
		# Note $pageobjs is a reference to an array, where each element is a hash reference (PObject).
		$this->{PObject} = $pageobjs->[0];
		# Now we make sure the Contents and Annots are arrays, and record their sizes.
		my( $contents, $annots );
		my $pdata = $this->{PObject}->{Data};
		if( ref( $pdata->{Contents} ) eq 'PObject' ){
			if( ref( $pdata->{Contents}->{Data} ) eq 'PArray' ){
				$contents = $pdata->{Contents}->{Data};
			} else {	# PRef
				$contents = $pdata->{Contents} = bless [ $pdata->{Contents} ], 'PArray';
			}
		} elsif( !exists $pdata->{Contents} ){
			$contents = $pdata->{Contents} = bless( [ ], 'PArray' );
		} else {	# Direct array object
			$contents = $pdata->{Contents};
		}
		if( exists $pdata->{Annots} ){
			if( ref( $pdata->{Annots} ) eq 'PObject' ){
				if( ref( $pdata->{Annots}->{Data} ) eq 'PArray' ){
					$annots = $pdata->{Annots}->{Data};
				} else {	# PRef
					$annots = $pdata->{Annots} = bless [ $pdata->{Annots} ], 'PArray';
				}
			} else {	# Direct array object
				$annots = $pdata->{Annots};
			}
		} else {
			$annots = [ ];
			$pdata->{Annots} = bless [ ], 'PArray';
		}
		# 08/20/2002 fix: each element of the Annots array could be a direct PDict, although rare.
		for my $aref ( @$annots ){
			if( ref( $aref ) eq 'PObject' ){
				$aref->{Data}->{P} = $this;
			} else {
				$aref->{P} = $this;
			}
		}
		# The following hash holds information about the original sizes of the arrays in the imported page.
		$this->{ImportArrays} = {
			'Contents' => scalar @$contents,	# v3.0: Number of elements in original contents array
			'Annots' => scalar @$annots,
			'ContentsStart' => 0,	# Jun 30, 2002: Start index of the original contents array in modified array
		};
		if( exists $attr->{AlwaysOnTop} ){
			$this->{AlwaysOnTop} = $attr->{AlwaysOnTop};
		}
		my $mb = $this->{PObject}->{Data}->{MediaBox};
		if( ref( $mb ) eq 'PRef' ){
			$mb = $attr->{ImportSource}->getObjectByRef( $mb )->parseIt( )->{Data};
		}
		@{$this->{MediaBox}} = ( $mb->[0]->[0], $mb->[1]->[0], $mb->[2]->[0], $mb->[3]->[0] );
	}
	# New feature in version 2.5: create objects from template definition.
	# If MultiRefer is set, just refer to the same object in the new page, otherwise a new object is created.
	my @TemplateObjects = $PDF::root->getTemplate( );
	# The "Template" defined in the $attr overwrites the current collection of template objects.
	if( ref( $attr ) eq 'HASH' && defined $attr->{Template} ){
		my $xmlparser = new XML::Parser( Style => 'Objects', ProtocolEncoding => 'ISO-8859-1' );
		# If a file name, read the content
		if( $attr->{Template} !~ m/[<>]/ && $attr->{Template} =~ /\.(tpl|xml)$/i ){	# Read from file
			$attr->{Template} =~ s/[\|<>]//g;	# Remove suspicious chars in a file name.
			$attr->{Template} = &PDF::secureFileName( $attr->{Template} );
			my $tmpfh = new FileHandle( $attr->{Template}, "r" ) or croak "Can't open file $attr->{Template}";
			$attr->{Template} = join( '', $tmpfh->getlines( ) );
			$tmpfh->close( );
		}
		# If xml content, parse it
		if( $attr->{Template} =~ m/[<>]/ ){	# Unparsed xml content
			my $xml = $attr->{Template};
			if( !exists $attr->{Parms} ){
				$attr->{Parms} = {};
			} elsif( ref( $attr->{Parms} ) ne 'HASH' ){
				my @tokens = map { split( /\s*:\s*/, $_, 2 ) } split( /\s*;\s*/, $attr->{Parms} );
				$attr->{Parms} = { @tokens };
				for( values %{$attr->{Parms}} ){ s/%([0-9A-Fa-f]{2})/pack('c',hex($1))/ge };
			}
			$attr->{Parms}->{PAGENUM} = $PDF::root->getPageCount( );
			$attr->{Parms}->{PAGELABEL} = $PDF::root->getCatalog( )->getNextPageLabel( ); # Added 12/23/2002
			$attr->{Parms}->{TIME} = scalar localtime( time );
			$attr->{Parms}->{TITLE} = $PDF::root->getTitle( );
			$attr->{Parms}->{SUBJECT} = $PDF::root->getSubject( );
			$attr->{Parms}->{AUTHOR} = $PDF::root->getAuthor( );
			$xml =~ s{(<Parms>.+<\/Parms>)}{}s;	# Find default parameters
			if( $1 ){
				my $parms = $xmlparser->parse( $1 )->[0];
				for my $node ( @{$parms->{Kids}} ){
					next if( ref( $node ) !~ /Parm$/ );
					if( !defined $attr->{Parms}->{ $node->{Name} } ){
						$attr->{Parms}->{ $node->{Name} } = $node->{Value};
					}
				}
			}
			if( exists $attr->{Parms} ){	# Replace parameters in template content
				$xml =~ s/%(\w+)%/$attr->{Parms}->{$1}/gs;
			}
			$attr->{Template} = $xmlparser->parse( $xml )->[0];
		}
		# If parsed, traverse it
		if( ref( $attr->{Template} ) =~ /\bTemplate$/ ){
			if( $attr->{Template}->{PageSize} ){	# Redefine page size
				@{$PDF::root->{Catalog}->{Pages}->{MediaBox}} = @{$this->{MediaBox}} = ( 0, 0, @{$Pages::PageSizes{ $attr->{Template}->{PageSize} }} );
			}
			if( !exists $attr->{Template}->{Name} ){ $attr->{Template}->{Name} = ''; }
			if( exists $attr->{Template}->{Width} ){ $this->{MediaBox}->[2] = &PDF::tellSize( $attr->{Template}->{Width} ); }
			if( exists $attr->{Template}->{Height} ){ $this->{MediaBox}->[3] = &PDF::tellSize( $attr->{Template}->{Height} ); }
			$this->recalcBoxes( $attr->{Template} );
			&PDF::resetTemplate( );	# Redefine template collection.
			@TemplateObjects = ( );			# Clean up current collection of template objects.
			for my $node ( @{$attr->{Template}->{Kids}} ){
				$node->{IsTemplate} = "1";
				$node->{InternalUse} = $this->{InternalUse};
				my $class = ref( $node );
				$class =~ s/^(\w+::)*//;
				# Next line: if the tag defines a resource, then there is no need to build a same resource again from the template because it would never be referred.
				if( { Shading=>1, Texture=>1, Font=>1, Image=>1, XObject=>1 }->{ $class } ){
					next if( !defined $node->{Name} );	# Anything without a name is NOT imported as they would never be referred to.
					next if( $PDF::root->checkTplRes( $attr->{Template}->{Name}, $node->{Name} ) );
				}
				if( defined $PDF::PDFeverModules{ $class } ){
					my $obj = &{ $PDF::PDFeverModules{ $class } }( $node );
					$this->appendContent( $obj ) if( $this->{InternalUse} && ( $class eq 'Text' || $class eq 'Graph' ) );
				}
			}
		} else {	# $attr->{Template} is a collection of object names
			my @names = ( $attr->{Template} =~ /([\d\w]+)/gs );
			for( @names ){
				push( @TemplateObjects, &PDF::getObjByName( $_ ) );
			}
		}
	}
	# Duplicate page contents so that a page can be edited afterwards.
	for my $obj ( @TemplateObjects ){
		next unless( $obj && ref( $obj ) );
		push( @{$this->{TplObjNames}}, $obj->{Name} ) unless( ref( $obj ) eq 'TextContent' );
		ref( $obj ) eq 'GraphContent' && do { $PDF::root->{Prefs}->{NoMultiRefer}? new GraphContent( $obj ): push( @{$this->{Contents}}, $obj ); next; };
		ref( $obj ) eq 'FloatingText' && do { $PDF::root->{Prefs}->{NoMultiRefer}? new FloatingText( $obj ): push( @{$this->{Contents}}, $obj ); next; };
		ref( $obj ) eq 'PreformText' && do { $PDF::root->{Prefs}->{NoMultiRefer}? new PreformText( $obj ): push( @{$this->{Contents}}, $obj ); next; };
		ref( $obj ) eq 'TextContent' && do { my $t = new TextContent( $obj ); $t->importText( ); next; };
	}
	unless ( $this->{InternalUse} ){
		if( $attr->{IsDefault} && $PDF::root->getPagesRoot->getPageByNumber( 0 ) != $this ){
			$PDF::root->getCatalog( )->setOpenPage( $this );
			$this->{IsDefault} = 1;
		}
		if( exists $attr->{XObject} ){
			return new XObject( $this, { 'Name' => $attr->{XObject}->{Name} } );
		}
	}
	$this->recalcBoxes( $attr );
	return $this;
}

sub recalcBoxes {
	my( $this, $attr ) = @_;
	# Margins are up to four values in the order of Left, Top, Right, Bottom
	if( $attr->{Margins} ){
		if( ref( $attr->{Margins} ) eq 'ARRAY' ){
			$this->crop( @{$attr->{Margins}}[0..3] );
		} else {
			$this->crop( split( /,\s*/, $attr->{Margins} ) );
		}
	} elsif( exists $PDF::root->{Prefs}->{Margins} ){
		if( ref( $PDF::root->{Prefs}->{Margins} ) eq 'ARRAY' ){
			$this->crop( @{$PDF::root->{Prefs}->{Margins}}[0..3] );
		} else {
			$this->crop( split( /,\s*/, $PDF::root->{Prefs}->{Margins} ) );
		}
	} else {
		@{$this->{CropBox}} = @{$this->{MediaBox}};
	}
	# Paddings are similar to Margins but are applied to ArtBox
	if( $attr->{Paddings} ){
		if( ref( $attr->{Paddings} ) eq 'ARRAY' ){
			$this->pad( @{$attr->{Paddings}}[0..3] );
		} else {
			$this->pad( split( /,\s*/, $attr->{Paddings} ) );
		}
	} elsif( exists $PDF::root->{Prefs}->{Paddings} ){
		if( ref( $PDF::root->{Prefs}->{Paddings} ) eq 'ARRAY' ){
			$this->crop( @{$PDF::root->{Prefs}->{Paddings}}[0..3] );
		} else {
			$this->crop( split( /,\s*/, $PDF::root->{Prefs}->{Paddings} ) );
		}
	} else {
		@{$this->{ArtBox}} = @{$this->{MediaBox}};
	}
	$PDF::root->resetAllTables( );	# Undefine any table definitions on previous page
	$PDF::root->setCurrTable( new TableGrid( 1, 1, [ new Rect( @{$this->{ArtBox}} ) ] ) );	# The page as a default big cell
}

sub crop {
	my( $this, @mgs ) = @_;	# Sequence: Left, Bottom, Right, Top (all positive)
	@{$this->{CropBox}} = @{$this->{MediaBox}};
	for( @mgs ){
		$_ = &PDF::tellSize( $_ );
	}
	if( @mgs == 1 ){ $mgs[1] = $mgs[0];	}
	if( @mgs == 2 ){ $mgs[2] = $mgs[0]; }
	if( @mgs == 3 ){ $mgs[3] = $mgs[1];	}
	$mgs[2] *= -1;
	$mgs[3] *= -1;
	for( @{$this->{CropBox}} ){
		$_ += shift( @mgs );
	}
	if( $this->{PObject} ){
		$this->{PObject}->{Data}->{CropBox} = bless [
			map { bless [ $_ ], 'PNumber'; } @{$this->{CropBox}}
		], 'PArray';
	}
}

sub pad {
	my( $this, @mgs ) = @_;	# Sequence: Left, Bottom, Right, Top (all positive)
	@{$this->{ArtBox}} = @{$this->{MediaBox}};
	for( @mgs ){
		$_ = &PDF::tellSize( $_ );
	}
	if( @mgs == 1 ){ $mgs[1] = $mgs[0];	}
	if( @mgs == 2 ){ $mgs[2] = $mgs[0]; }
	if( @mgs == 3 ){ $mgs[3] = $mgs[1];	}
	$mgs[2] *= -1;
	$mgs[3] *= -1;
	for( @{$this->{ArtBox}} ){
		$_ += shift( @mgs );
	}
	if( $this->{PObject} ){
		$this->{PObject}->{Data}->{ArtBox} = bless [
			map { bless [ $_ ], 'PNumber'; } @{$this->{ArtBox}}
		], 'PArray';
	}
}

sub getCropBox {
	return new Rect( @{shift->{CropBox}} );
}

sub getArtBox {
	return new Rect( @{shift->{ArtBox}} );
}

sub getMediaBox {
	return new Rect( @{shift->{MediaBox}} );
}

sub rotate {
	my( $this, $dir ) = @_;
	if( $dir > 0 && $dir < 4 ){
		$this->{Rotation} = int( $dir );
	}
}

sub appendContent {
	my ( $this, $oContent ) = @_;
	if( $oContent->{par} == $this ){
		return $oContent;
	}
	if( $oContent->{par} && $oContent->{par} != $this ){
		my $par = $oContent->{par};
		$par->deleteChild( $oContent );
		@{$par->{Contents}} = grep { $_ == $oContent? undef: $oContent } @{$par->{Contents}};
	}
	push( @{$this->{Contents}}, $oContent );
	$this->appendChild( $oContent );
	return $oContent;
}

sub appendAnnot {
	my ( $this, $oAnnot, $NoAppend ) = @_;
	if( !$oAnnot->{par} || $NoAppend ){
		push( @{$this->{Annots}}, $oAnnot );
		$this->appendChild( $oAnnot ) unless( $NoAppend );
	}
	return $oAnnot;
}

# Following three appendXXX methods used to append the objects to current page
# only; now the resources have been made global so that all pages will share,
# and the "Resources" term is removed from the PDF output.
sub appendShading {
	my ( $this, $oShading ) = @_;
	return $this->{par}->appendShading( $oShading );
}

sub appendPattern {
	my ( $this, $oPattern ) = @_;
	return $this->{par}->appendPattern( $oPattern );
}

sub appendColorSpace {
	my ( $this, $oSpace ) = @_;
	return $this->{par}->appendColorSpace( $oSpace );
}

%Page::AppendMethods = (
	GraphContent => \&appendContent,
	TextContent => \&appendContent,
	FloatingText => \&appendContent,
	PreformText => \&appendContent,
	Annot => \&appendAnnot,
	PDFShading => \&appendShading,
	PDFTexture => \&appendPattern,
	ColorSpace => \&appendColorSpace,
);

sub add {
	my( $this, $that ) = @_;
	if( defined $Page::AppendMethods{ ref( $that ) } ){
		&{$Page::AppendMethods{ ref( $that ) }}( $this, $that );
	}
	return $that;
}

sub swapPage {
	my( $this, $that ) = @_;
	$PDF::root->getPagesRoot( )->swapPage( $this, $that );
}

sub getObjId {
	my $this = shift;
	return $this->{PObject}? $this->{PObject}->{ObjId}: $this->{ObjId};
}

sub getWidth {
	my $this = shift;
	if( $this->{PObject} ){
		return $this->{PObject}->{Data}->{MediaBox}->[2]->[0];
	}
	return $this->{MediaBox}->[2];
}

sub getHeight {
	my $this = shift;
	if( $this->{PObject} ){
		return $this->{PObject}->{Data}->{MediaBox}->[3]->[0];
	}
	return $this->{MediaBox}->[3];
}

sub drawTable {
	my $this = shift;
	if( !$this->{Graphics} ){
		$this->{Graphics} = new GraphContent( $this->getArtBox( ) );
		$this->appendContent( $this->{Graphics} );
	}
	$this->{Graphics}->drawGrid( @_ );
}

sub drawTableAt {
	my $this = shift;
	if( !$this->{Graphics} ){
		$this->{Graphics} = new GraphContent( $this->getArtBox( ) );
		$this->appendContent( $this->{Graphics} );
	}
	$this->{Graphics}->drawGridAt( @_ );
}

sub getGraphics {
	my $this = shift;
	if( !$this->{Graphics} ){
		$this->{Graphics} = new GraphContent( new Rect( 0, 0, $this->getWidth( ), $this->getHeight( ) ) );
		$this->appendContent( $this->{Graphics} );
	}
	return $this->{Graphics};
}

sub getResources {
	my $this = shift;
	$this->{Resources} = new Resources( );
	for my $kid ( @{$this->{Contents}} ){
		next if( !defined $kid->{Resources} );
		$this->{Resources}->merge( $kid->{Resources} );
	}
	return $this->{Resources};
}

# Incorporate the resources TO the dictionary defined in the PObject
# The original resource data is saved since this function can be called multiple times.
sub mergeResources {
	my $this = shift;
	return if( !$this->{PObject} );
	# Get the resource dictionary of the imported page object (must be a PDict).
	# PDFever uses ProcSet, XObject, Shading, Pattern, ColorSpace, and ExtGState.
	my $ImpResDict = ref( $this->{PObject}->{Data}->{Resources} ) eq 'PObject'?
		$this->{PObject}->{Data}->{Resources}->{Data}: $this->{PObject}->{Data}->{Resources};
	# Robust fix 10/03/2002: If the resources data is not a dictionary (such as 'null'), then fix it.
	if( ref( $ImpResDict ) ne 'PDict' ){
		if( ref( $this->{PObject}->{Data}->{Resources} ) eq 'PObject' ){
			$ImpResDict = $this->{PObject}->{Data}->{Resources}->{Data} = bless { }, 'PDict';
		} else {
			$ImpResDict = $this->{PObject}->{Data}->{Resources} = bless { }, 'PDict';
		}
	}

	# ProcSet entry
	if( defined $ImpResDict->{ProcSet} ){
		my $procset = ref( $ImpResDict->{ProcSet} ) eq 'PArray'?
			$ImpResDict->{ProcSet}: $ImpResDict->{ProcSet}->{Data};
		my %definedsets = map { $_->[0] => 1 } @$procset;
		for( $PDF::root->getPagesRoot( )->getProcSet( ) ){
			next if( defined $definedsets{$_} );
			push( @$procset, ( bless [ $_ ], 'PName' ) );
		}
	} else {
		$ImpResDict->{ProcSet} = bless [
			map { bless [ $_ ], 'PName' } keys %{$PDF::root->{Catalog}->{Pages}->{ProcSet}}
		], 'PArray';
	}

	# The following hash holds information about renamed resources, which has to be between two passes of writing PDF code.
	%{$this->{RenamedResources}} = ( );
	# Now we merge other entries
	for my $resname ( keys %{$this->{Resources}} ){
		next unless( keys %{$this->{Resources}->{$resname}} );
		if( !exists $ImpResDict->{$resname} ){
			$ImpResDict->{$resname} = bless { }, 'PDict';
		}
		my $pdict = ref( $ImpResDict->{$resname} ) eq 'PDict'?
			$ImpResDict->{$resname}: $ImpResDict->{$resname}->{Data};
		# For each resource item in each category, do the following:
		for my $name ( keys %{$this->{Resources}->{$resname}} ){
			# When there's a name confliction, rename my own resource item;
			# otherwise just add an entry into the imported page's resources.
			my $item = $PDF::root->getObjByName( $name );
			if( exists $pdict->{$name} && !exists $this->{ExportedNames}->{$name} ){
				do {
					$name++;
				} while( $PDF::root->getObjByName( $name ) || defined $pdict->{$name} );
			}
			for my $child ( @{$this->{Contents}} ){
				if( $child->{par} != $this ){
					next if( !exists $child->{par}->{RenamedResources}->{$resname} );
					my %names = reverse %{$child->{par}->{RenamedResources}->{$resname}};
					$name = $names{$item->{Name}};
					$this->{RenamedResources}->{$resname}->{$name} = $item->{Name};
				} elsif( $name ne $item->{Name} ){	# Name changed? If so, change the stream data.
					$child->{Stream} =~ s/\/$item->{Name}\b/\/$name/gs;
					$this->{RenamedResources}->{$resname}->{$name} = $item->{Name};
				}
			}
			# Now it is safe to merge the resources entry
			$this->{ExportedNames}->{$name} = 1;
			$pdict->{$name} = $item;	# bless { 'ObjId' => $item->{ObjId}, 'GenId' => 0 }, 'PRef';
		}
	}
}

sub makeCode {
	my $this = shift;
	# Now we merge the data with those in a referred page from an existing PDF file, if any.
	# If so, the PObject will take care of the code output. The Page will just be a proxy.
	$this->getResources( );
	# Revision 06/30/02: treat contents differently -- check their z-indices (zero, positive, negative)
	my @ContentsZero = grep { !defined $_->{ZIndex} || $_->{ZIndex} == 0 } @{$this->{Contents}};
	my @ContentsPositive = sort { $a->{ZIndex} <=> $b->{ZIndex} } grep { defined $_->{ZIndex} && $_->{ZIndex} > 0 } @{$this->{Contents}};
	my @ContentsNegative = sort { $a->{ZIndex} <=> $b->{ZIndex} } grep { defined $_->{ZIndex} && $_->{ZIndex} < 0 } @{$this->{Contents}};
	if( $this->{PObject} ){
		# Here, the Contents of the PObject is set to PArray, if it is a PRef:
		# 1. An array of reference to PObjects, each being a content stream;
		# 2. Reference to a PObject, which is a content stream;
		# 3. Reference to a PObejct, which is an array of PObject refs.
		my $pdata = $this->{PObject}->{Data};
		my $contents = ref( $pdata->{Contents} ) eq 'PArray'? $pdata->{Contents}: $pdata->{Contents}->{Data};
		# We have to remove modifications made in last run of makeCode
		@$contents = splice( @$contents, $this->{ImportArrays}->{ContentsStart}, $this->{ImportArrays}->{Contents} );
		if( $this->{AlwaysOnTop} ){
#			splice( @$contents, 0, @$contents - $this->{ImportArrays}->{Contents} );
			for( reverse ( @ContentsNegative, @ContentsZero ) ){
				unshift( @$contents, bless { 'ObjId' => $_->{ObjId}, 'GenId' => 0 }, 'PRef' );
			}
			$this->{ImportArrays}->{ContentsStart} = scalar( @ContentsNegative ) + scalar( @ContentsZero );
			for( @ContentsPositive ){
				push( @$contents, bless { 'ObjId' => $_->{ObjId}, 'GenId' => 0 }, 'PRef' );
			}
		} else {
#			splice( @$contents, $this->{ImportArrays}->{Contents} );
			for( reverse @ContentsNegative ){
				unshift( @$contents, bless { 'ObjId' => $_->{ObjId}, 'GenId' => 0 }, 'PRef' );
			}
			$this->{ImportArrays}->{ContentsStart} = scalar @ContentsNegative;
			for( @ContentsZero, @ContentsPositive ){
				push( @$contents, bless { 'ObjId' => $_->{ObjId}, 'GenId' => 0 }, 'PRef' );
			}
		}
		# $annots will point to an array ref.
		my $annots = ref( $pdata->{Annots} ) eq 'PArray'? $pdata->{Annots}: $pdata->{Annots}->{Data};
		splice( @$annots, $this->{ImportArrays}->{Annots} );
		for( @{$this->{Annots}} ){
			push( @$annots, bless { 'ObjId' => $_->{ObjId}, 'GenId' => 0 }, 'PRef' );
		}
		$this->mergeResources( );
		if( $this->{Rotation} ){
			$this->{PObject}->{Data}->{Rotate} = bless [ [ 0, 90, 270, 180 ]->[ $this->{Rotation} ] ], 'PNumber';
		}
		$pdata->{Parent} = bless { 'ObjId' => $PDF::root->getPagesRoot( )->findParent( $this ), 'GenId' => 0 }, 'PRef';
		return;
	}
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Type /Page ',
		sprintf( '/Parent %d 0 R ', $PDF::root->getPagesRoot( )->findParent( $this ) ),
		'/Contents [ ' . join( ' ', map { "$_->{ObjId} 0 R" } ( @ContentsNegative, @ContentsZero, @ContentsPositive ) ) . ' ] ',
		'/Annots [ ' . join( ' ', map { "$_->{ObjId} 0 R" } @{$this->{Annots}} ) . ' ] ',
		'/MediaBox [ ' . join( ' ', @{$this->{MediaBox}} ) . ' ] ',
		'/CropBox [ ' . join( ' ', @{$this->{CropBox}} ) . ' ] ',
		'/ArtBox [ ' . join( ' ', @{$this->{ArtBox}} ) . ' ] ',
	);
	if( $this->{Duration} ){
		print qq{$PDF::endln/Dur $this->{Duration} };
	}
	if( $this->{Trans} ){
		print qq{$PDF::endln/Trans <<$PDF::endln/Type /Trans$PDF::endln/S /$Page::TransTypes[$this->{Trans}] };
		if( $this->{TransDur} ){
			print qq{$PDF::endln/D $this->{TransDur} };
		}
		if( $this->{Trans} <= 2 ){
			print qq{$PDF::endln/Dm /$this->{Dimension} };
		} elsif( $this->{Trans} == 4 || $this->{Trans} == 6 ){
			print qq{$PDF::endln/Di /$this->{Direction} };
		}
		if( $this->{Trans} == 1 || $this->{Trans} == 3 ){
			print qq{$PDF::endln/M /$this->{Motion} };
		}
		print qq{$PDF::endln>> };
	}
	if( $this->{Rotation} ){
		print $PDF::endln . '/Rotate ' . [ 0, 90, 270, 180 ]->[ $this->{Rotation} ];
	}
	print "$PDF::endln/Resources <<$PDF::endln";
	print '/ProcSet [ /', join( ' /', $PDF::root->getPagesRoot( )->getProcSet( ) ), ' ]', $PDF::endln;
	for my $res ( keys %{$this->{Resources}} ){
		next unless( keys %{$this->{Resources}->{$res}} );	# The resource category should contain some names
		print "/$res <<";
		map { printf( "/%s %d 0 R ", $_, $PDF::root->getObjByName( $_ )->{ObjId} ); } keys %{$this->{Resources}->{$res}};
		print ">>$PDF::endln";
	}
	print ">>$PDF::endln";
	print join( $PDF::endln,
		'>> ',
		'endobj',
		''
	);
}

sub cleanUp {
	my $this = shift;
	return if( !$this->{PObject} );
	for my $resname ( keys %{$this->{RenamedResources}} ){
		for my $key ( keys %{$this->{RenamedResources}->{$resname}} ){
			for my $child ( @{$this->{Contents}} ){
				$child->{Stream} =~ s/\/$key\b/\/$this->{RenamedResources}->{$resname}->{$key}/gs;
			}
		}
	}
	my $ImpResDict = ref( $this->{PObject}->{Data}->{Resources} ) eq 'PObject'?
		$this->{PObject}->{Data}->{Resources}->{Data}: $this->{PObject}->{Data}->{Resources};
	for my $resname ( keys %{$this->{Resources}} ){
		next if( !defined $ImpResDict->{$resname} );	# Check the existence of the dictionary entry
		my $pdict = ref( $ImpResDict->{$resname} ) eq 'PDict'?
			$ImpResDict->{$resname}: $ImpResDict->{$resname}->{Data};
		for( keys %$pdict ){
			if( defined $this->{Resources}->{$_} ){
				delete $pdict->{$_};
			}
		}
	}
	$this->{Resources} = undef;
}

sub startXML {
	my( $this, $dep ) = @_;
	print "\t" x $dep, '<', ref( $this ), ' Name="', &PDF::escXMLChar( $this->{Name} ),
		'" Width="', $this->{MediaBox}->[2], '" Height="', $this->{MediaBox}->[3], '"';
	for( qw(Size Rotation) ){
		next unless( $this->{$_} );
		print qq{ $_="} . &PDF::escXMLChar( $this->{$_} ) . '"';
	}
	if( defined $this->{XObject} ){
		print ' XObject="', &PDF::escXMLChar( $this->{XObject}->{Name} ), '"';
	}
	if( defined $this->{ImportSource} ){
		print qq{ ImportSource="$this->{ImportSource}" ImportPage="$this->{ImportPage}"};
		print qq{ SkipAnnots="1"} if( $this->{SkipAnnots} );
		print qq{ AlwaysOnTop="1"} if( $this->{AlwaysOnTop} );
	}
	if( $this->{Trans} ){
		for( qw(Trans Duration TransDur Direction Dimension Motion) ){
			next unless( $this->{$_} );
			print qq{ $_="} . &PDF::escXMLChar( $this->{$_} ) . '"';
		}
	} elsif( $this->{Duration} ){
		print qq{ Duration="$this->{Duration}"};
	}
	if( @{$this->{TplObjNames}} ){
		print ' Template="', join( ', ', @{$this->{TplObjNames}} ), '"';
	}
	if( defined $this->{IsDefault} ){
		print ' IsDefault="1"';
	}
	print ">\n";
}

sub endXML {
	my( $this, $dep ) = @_;
	print "\t" x $dep, '</', ref( $this ), ">\n";
}

sub newFromXML {
	my( $class, $xml ) = @_;
	if( $xml->{Width} && $xml->{Height} ){
		$xml->{Box} = new Rect( 0, 0, $xml->{Width}, $xml->{Height} );
	}
	if( defined $xml->{ImportSource} ){
		$xml->{ImportSource} = $PDF::root->getImportedFile( $xml->{ImportSource} );
	}
	return new Page( bless $xml, 'HASH' );
}

sub finalize {
	my $this = shift;
	if( $this->{PObject} ){
		undef $this->{PObject};
		@{$this->{PObjectArray}} = ( );
	}
	@{$this->{Contents}} = ( );
	@{$this->{Annots}} = ( );
	undef $this->{XObject};
}

1;
