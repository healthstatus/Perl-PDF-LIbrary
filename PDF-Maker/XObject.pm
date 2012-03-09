#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package XObject;

use Page;
use PDFStream;
use Compress::Zlib;

@ISA = qw(PDFStream Page);

sub new {
	my( $class, $param ) = @_;
	my $this;
	if( ref( $param ) eq 'Page' ){
		my $page = $param;
		$param = shift;
		if( !defined $param || ref( $param ) ne 'HASH' ){
			$param = { 'InternalUse' => 1 };
		} else {
			$param->{InternalUse} = 1;
		}
		# A page can be defined as an XObject only once.
		if( defined $page->{XObject} ){
			return $page->{XObject};
		}
		$this = bless Page->new( $param ), $class;
		$this->{PageRef} = $page;
		$page->{XObject} = $this;	# Note this circular reference!
		$this->{DisplayWidth} = $this->{Width} = $page->{MediaBox}->[2];
		$this->{DisplayHeight} = $this->{Height} = $page->{MediaBox}->[3];
	} else {
		if( ref( $param ) eq 'Rect' ){
			my $rect = new Rect( $param );
			$param = { 'Box' => $rect, 'InternalUse' => 1 };
		} elsif( ref( $param ) eq 'HASH' ){
			$param->{InternalUse} = 1;
		} else {
			$param = { 'InternalUse' => 1, 'Size' => $param };
		}
		$this = bless Page->new( $param ), $class;
		$this->{DisplayWidth} = $this->{Width} = $this->{MediaBox}->[2];
		$this->{DisplayHeight} = $this->{Height} = $this->{MediaBox}->[3];
		$this->{PageRef} = 0;	# Standalone XObject
		# Now cut off tree links to avoid unnecessary code generation
		for my $child ( @{$this->{Contents}} ){
			$this->deleteChild( $child );
		}
	}
	$this->{Stream} = '';	# Always initiated empty; rewritten every time PDF is printed
	$this->{Filters} = [ ];
	$this->{DecodeParms} = [ ];
	$PDF::root->{Catalog}->{Pages}->appendXObject( $this );
	return $this;
}

# Only put the child into the Contents array but not link it to the tree
sub appendContent {
	my( $this, $child ) = @_;
	$this->SUPER::appendContent( $child );
	$this->deleteChild( $child );
}

# Overriding that one defined in Page. Copy the merged data FROM the PObject TO this XObject.
sub mergeResources {
	my $this = shift;
	$this->SUPER::mergeResources( );
	$this->{Resources} = new Resources( );
	my $ImpResDict;
	if( ref( $this->{PObject}->{Data}->{Resources} ) eq 'PObject' ){
		$ImpResDict = $this->{PObject}->{Data}->{Resources}->{Data};
		$PDF::root->excludePObject( $this->{PObject}->{Data}->{Resources} );
	} else {
		$ImpResDict = $this->{PObject}->{Data}->{Resources};
	}
	for my $resname ( keys %$ImpResDict ){
		next if( $resname eq 'ProcSet' );
		my $pdict;
		if( ref( $ImpResDict->{$resname} ) eq 'PDict' ){
			$pdict = $ImpResDict->{$resname};
		} else {
			$PDF::root->excludePObject( $ImpResDict->{$resname} );
			$pdict = $ImpResDict->{$resname}->{Data};
		}
		for( keys %$pdict ){
			$this->{Resources}->{$resname}->{$_} = $pdict->{$_};
		}
	}
	return $this->{Resources};
}

sub customCode {
	my $this = shift;
	$this->getResources( );	# Get the resources for its own content objects.
	if( $this->{PageRef} ){	# If the XObject is modeled after a previous page, get the resources and merge them.
		$this->{Resources}->merge( $this->{PageRef}->getResources( ) );
	}
	if( $this->{PObject} ){	# Imported page from an existing PDF file
		$PDF::root->excludePObject( $this->{PObject} );
		$this->mergeResources( );
		my $contents;
		my $pdata = $this->{PObject}->{Data};
		if( ref( $pdata->{Contents} ) eq 'PObject' ){	# Indirect object
			if( ref( $pdata->{Contents}->{Data} ) eq 'PArray' ){	# Array of indirect objects
				$contents = $pdata->{Contents}->{Data};
			} else {	# A single content stream
				$contents = $pdata->{Contents} = bless [ $pdata->{Contents} ], 'PArray';
			}
		} else {
			$contents = $pdata->{Contents};	# Array of indirect objects (content streams)
		}
		# At this stage, $contents is an array
		for my $child ( @$contents ){
			$PDF::root->excludePObject( $child );
			my $data = $child->{Data};
			if( ref( $data->{Length} ) eq 'PObject' ){
				$PDF::root->excludePObject( $data->{Length} );
			}
			if( defined $data->{Filter} ){
				if( ref( $data->{Filter} ) eq 'PName' && $data->{Filter}->[0] eq 'FlateDecode' ||
					ref( $data->{Filter} ) eq 'PArray' && scalar @{$data->{Filter}} == 1 && $data->{Filter}->[0]->[0] eq 'FlateDecode' ){
					$this->{Stream} .= Compress::Zlib::uncompress( $child->getStreamData( ) ) . ' ';	# Need a space to avoid concatenation of chars
				} else {
					next;
				}
			} else {
				$this->{Stream} .= $child->getStreamData( ) . ' ';
			}
		}
	}
	print join( $PDF::endln,
		'',
		'/Type /XObject ',
		'/Subtype /Form ',
		'/FormType 1 ',
		join( ' ', '/BBox [', @{ $this->{PageRef}? $this->{PageRef}->{CropBox}: $this->{CropBox} }, ']' ),
		'/Resources <<',
		join( ' /', '/ProcSet [', $PDF::root->getPagesRoot( )->getProcSet( ) ),
		']',
	);
	for my $res ( keys %{$this->{Resources}} ){
		next unless( keys %{$this->{Resources}->{$res}} );
		print "$PDF::endln/$res <<";
		my $dict = $this->{Resources}->{$res};
		for my $obj ( keys %$dict ){
			if( ref( $dict->{$obj} ) eq 'PObject' ){
				printf( "/%s %d 0 R ", $obj, $dict->{$obj}->{ObjId} );
			} elsif( ref( $dict->{$obj} ) eq 'PArray' ){
				print "/$obj ";
				PDF::printPDF( $dict->{$obj} );
			} else {
				printf( "/%s %d 0 R ", $obj, $PDF::root->getObjByName( $obj )->getObjId( ) );
			}
		}
		print ">>";
	}
	print "$PDF::endln>>$PDF::endln";
	$this->{Stream} .= ' q ';
	my $cont = $this->{PageRef}? $this->{PageRef}->{Contents}: $this->{Contents};
	for my $child ( @$cont ){
		$this->{Stream} .= ' Q q ';
		$this->{Stream} .= $child->{Stream};
	}
	$this->{Stream} .= ' Q ';
}

sub cleanUp {
	my $this = shift;
	$this->{Stream} = '';
}

sub startXML {
	my( $this, $dep ) = @_;
	# If the XObject is created from a Page, then the Page will create the tag
	if( !defined $this->{PageRef} ){
		Page::startXML( $this, $dep );
		return;
	}
}

sub endXML {
	my( $this, $dep ) = @_;
	if( !defined $this->{PageRef} ){
		Page::endXML( $this, $dep );
	}
}

sub newFromXML {
	my( $class, $xml ) = @_;
	if( $xml->{Width} && $xml->{Height} ){
		$xml->{Box} = new Rect( 0, 0, $xml->{Width}, $xml->{Height} );
	}
	my $this = new XObject( bless $xml, 'HASH' );
	for my $node ( @{$xml->{Kids}} ){
		$node->{InternalUse} = 1;
		my $class = ref( $node );
		$class =~ s/^(\w+::)*//;
		if( defined $PDF::PDFeverModules{ $class } ){
			my $obj = &{ $PDF::PDFeverModules{ $class } }( $node );
			$this->appendContent( $obj );
		}
	}
}

sub finalize {
	my $this = shift;
	undef $this->{PageRef};
	undef $this->{Resources};
	$this->PDFStream::finalize( );
	$this->Page::finalize( );
}

1;
