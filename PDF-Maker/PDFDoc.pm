#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#
# Packages (only class PDFDoc public):
#	Catalog			Catalog, the "Root" field of PDF trailer dictionary
#	Color			Color-related names and routines
#	DocInfo			Document information, the "DocInfo" field of trailer
#	ExtGState		Extended graphics state
#	MetaData		MetaData packet conforming to Adobe XMP framework
#	Pages			Root node of the pages tree, singleton
#	PDFDoc			PDF document, tree root
#	PDFEncrypt		Encryption dictionary, the "Encrypt" field of trailer
#	Resources		Resources dictionary to be used in page objects
#	TableGrid		Table-based layout support

#===========================================================================#
# DocInfo
#===========================================================================#

package DocInfo;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $parm, $title, $subject, $producer ) = @_;	# For backward-compatibility with versions <= 2.4
	my $author = $parm;
	if( ref( $parm ) eq 'HASH' ){
		$author = undef;
		exists $parm->{Author} && do { $author = $parm->{Author} };
		exists $parm->{Title} && do { $title = $parm->{Title} };
		exists $parm->{Subject} && do { $subject = $parm->{Subject} };
		exists $parm->{Producer} && do { $producer = $parm->{Producer} };
	}
	if( !defined( $author ) && exists $PDF::root->{Prefs}->{Author} ){ $author = $PDF::root->{Prefs}->{Author}; }
	if( !defined( $title ) && exists $PDF::root->{Prefs}->{Title} ){ $title = $PDF::root->{Prefs}->{Title}; }
	if( !defined( $subject ) && exists $PDF::root->{Prefs}->{Subject} ){ $subject = $PDF::root->{Prefs}->{Subject}; }
	if( !defined( $producer ) && exists $PDF::root->{Prefs}->{Producer} ){ $producer = $PDF::root->{Prefs}->{Producer}; }
	my $this = {
		'Author' => $author,
		'CreationDate' => &PDF::tellTime( ),
		'Creator' => $PDF::ApplicationName,
		'Producer' => $producer,
		'Title' => $title,
		'Subject' => $subject,
		'Keywords' => '',	# A v3.0 addition
	};
	bless $this, $class;
	$PDF::root->appendChild( $this );
	$PDF::root->{DocInfo} = $this;
	$this->setFileID( );
	return $this;
}

# Will be called by constructor AND the writePDF function
sub setFileID {
	my $this = shift;
	$PDF::root->{FileID} = &PDF::MD5( $this->{Author}, $this->{Subject}, $this->{Title}, $this->{Producer}, ( scalar gmtime ), rand );
}

sub setKeywords {
	my( $this, @keywords ) = @_;
	$this->{Keywords} = join( '; ', @keywords );
}

sub setTitle {
	my $this = shift;
	$this->{Title} = shift;
}

sub setSubject {
	my $this = shift;
	$this->{Subject} = shift;
}

sub setAuthor {
	my $this = shift;
	$this->{Author} = shift;
}

sub setProducer {
	my $this = shift;
	$this->{Producer} = shift;
}

sub makeCode {
	my $this = shift;
	my %strs = ( );
	for my $ky ( qw(Author Creator Producer Title Subject Keywords CreationDate) ){
		next if( !exists $this->{$ky} );
		$strs{$ky} = &PDF::escStr(
			$PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{$ky} ): $this->{$ky}
		);
	}
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		qq{/Creator ($strs{Creator})},
		qq{/ModDate ($strs{CreationDate})},
		qq{/CreationDate ($strs{CreationDate})},
	);
	for my $ky ( qw(Author Title Subject Keywords Producer) ){
		next unless( length( $strs{$ky} ) );
		print $PDF::endln . qq{/$ky ($strs{$ky})};
	};
	print join( $PDF::endln,
		'',
		'>> ',
		'endobj',
		''
	);
}

#===========================================================================#
# MetaData
#===========================================================================#

package MetaData;

@ISA = qw(PDFStream);

sub new {
	my( $class, $attr ) = @_;
	my $this = new PDFStream( );
	$this->{XMP} = exists $attr->{XMP}? $attr->{XMP}: 1;
	$this->{PDF} = exists $attr->{PDF}? $attr->{PDF}: 1;
	$this->{DC} = exists $attr->{DC}? $attr->{DC}: 1;
	bless $this, $class;
}

sub customCode {
	my $this = shift;
	$this->{Stream} = $PDF::endln;
	$this->{Stream} .= q{<rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#' xmlns:iX='http://ns.adobe.com/iX/1.0/'>};
	$this->{Stream} .= $PDF::endln;
	my $info = $PDF::root->getDocInfo( );
	$info->{CreationDate} =~ /^D:(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(.\d{2})'(\d{2})'/;
	my $tm = "$1-$2-$3T$4:$5:$6$7:$8";
	
	if( $this->{PDF} ){
		$this->{Stream} .= q{<rdf:Description about='' xmlns='http://ns.adobe.com/pdf/1.3/' xmlns:pdf='http://ns.adobe.com/pdf/1.3/'>};
		$this->{Stream} .= $PDF::endln;
		for my $item ( qw(Producer Creator Author Title Subject Keywords) ){
			$this->{Stream} .= qq{<pdf:$item>} . PDF::escXMLChar( $info->{$item} ) . qq{</pdf:$item>$PDF::endln};
		}
		$this->{Stream} .= qq{<pdf:PDFVersion>$PDF::root->{Version}</pdf:PDFVersion>$PDF::endln};
		$this->{Stream} .= qq{<pdf:CreationDate>$tm</pdf:CreationDate>$PDF::endln};
		$this->{Stream} .= qq{</rdf:Description>$PDF::endln};
	}
	
	my $keywords = '';
	if( $this->{XMP} || $this->{DC} ){
		for( split( /; /, $this->{Keywords} ) ){
			$keywords .= q{<rdf:li xml:lang='x-default'>} . PDF::escXMLChar( $_ ) . qq{</rdf:li>$PDF::endln};
		}
		$keywords = qq{<rdf:Bag>$keywords</rdf:Bag>$PDF::endln};
	}

	if( $this->{XMP} ){	# Termed as XAP before XMP platform was proposed. xap:Title is an Alt, xap:Keywords is a Bag.
		$this->{Stream} .= q{<rdf:Description about='' xmlns='http://ns.adobe.com/xap/1.0/' xmlns:xap='http://ns.adobe.com/xap/1.0/'>};
		$this->{Stream} .= $PDF::endln;
		$this->{Stream} .= qq{<xap:CreateDate>$tm</xap:CreateDate>$PDF::endln};
		$this->{Stream} .= qq{<xap:MetadataDate>$tm</xap:MetadataDate>$PDF::endln};
		$this->{Stream} .= '<xap:Author>' . PDF::escXMLChar( $info->{Author} ) . qq{</xap:Author>$PDF::endln};
		$this->{Stream} .= qq{<xap:Keywords>$keywords</xap:Keywords>$PDF::endln};
		$this->{Stream} .= q{<xap:Title><rdf:Alt><rdf:li xml:lang='x-default'>} . PDF::escXMLChar( $info->{Title} ) . qq{</rdf:li></rdf:Alt></xap:Title>$PDF::endln};
		$this->{Stream} .= qq{</rdf:Description>$PDF::endln};
	}

	if( $this->{DC} ){	# dc:subject is xap:Keywords; dc:creator is xap:Author
		$this->{Stream} .= q{<rdf:Description about='' xmlns='http://purl.org/dc/elements/1.1/' xmlns:dc='http://purl.org/dc/elements/1.1/'>};
		$this->{Stream} .= $PDF::endln;
		$this->{Stream} .= qq{<dc:subject>$keywords</dc:subject>$PDF::endln};
		$this->{Stream} .= '<dc:creator>' . PDF::escXMLChar( $info->{Author} ) . qq{</dc:creator>$PDF::endln};
		$this->{Stream} .= '<dc:title>' . PDF::escXMLChar( $info->{Title} ) . qq{</dc:title>$PDF::endln};
		$this->{Stream} .= qq{</rdf:Description>$PDF::endln};
	}
	$this->{Stream} .= "</rdf:RDF>$PDF::endln<?xpacket end='r'?>";	# Read-only
	my $prefixleng = 68;	# The byte length of the first line, which has to contain the value of the total length. The 'id' is a fixed string.
	substr( $this->{Stream}, 0, 0 ) = sprintf( "%-${prefixleng}s", q{<?xpacket begin='' id='W5M0MpCehiHzreSzNTczkc9d' bytes='} . ( length( $this->{Stream} ) + $prefixleng ) . q{'?>} );
	print "$PDF::endln/Type /MetaData /Subtype /XML";
}

#===========================================================================#
# NamesTree
#===========================================================================#

package NamesTree;

@ISA = qw(PDFTreeNode);

sub new {
	my $class = shift;
	my $this = {
		Pages => { }
	};
	bless $this, $class;
}

sub addName {
	my( $this, $type, $name, $pgobj ) = @_;	# $pgobj could be Page or PObject
	$this->{$type}->{$name} = $pgobj;
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Type /Names ',
	);
	for my $type ( qw(Pages Dests) ){
		next if( !defined $this->{$type} );
		my @names = sort keys %{$this->{$type}};
		next unless( scalar @names > 0 );
		print "$PDF::endln/$type << /Limits [(",
			PDF::escStr( $names[0] ), ")(",
			PDF::escStr( $names[-1] ), ")] ";
		print "$PDF::endln/Names [";
		for( @names ){
			printf( "(%s) %d 0 R$PDF::endln", PDF::escStr( $_ ), $this->{$type}->{$_}->getObjId( ) );
		}
		print "] >>$PDF::endln";
	}
	print join( $PDF::endln,
		'',
		'>> ',
		'endobj',
		''
	);
}

sub finalize {
	my $this = shift;
	for my $type ( qw(Pages) ){
		%{$this->{$type}} = ( );
	}
}

#===========================================================================#
# Catalog
#===========================================================================#

package Catalog;

@ISA = qw(PDFTreeNode);
%PageModes = qw(UseNone 0 UseOutlines 1 UseThumbs 2 FullScreen 3);
%PageLayouts = qw(SinglePage 0 OneColumn 1 TwoColumnLeft 2 TwoColumnRight 3);

# Call as new( ), new( string ), or new( int, int, string )
sub new {
	my $class = shift;
	my $this = {
		AcroForm => undef,
		Pages => undef,
		Outlines => undef,
		MetaData => undef,
		PageMode => 'UseNone',
		PageLayout => 'SinglePage',
		PageLabels => [ ],
		PageLabel => '',
		DefaultPage => undef,
		Toolbar => 1,
		Menubar => 1,
		WindowUI => 1,
		FitWindow => 0,
		CenterWindow => 0,
		Threads => undef,	# For imported *whole* PDF file ONLY!
		Names => new NamesTree( ),	# If importing *whole* PDF file, this entry could be overridden!
	};
	bless $this, $class;
	$PDF::root->{Catalog} = $this;
	$PDF::root->appendChild( $this );
	$this->appendChild( $this->{Names} );
	my( $mode, $layout, $label ) = ( 0, 0, undef );
	if( @_ > 1 ){
		$mode = shift;
		$layout = shift;
	}
	$label = shift;
	if( defined $label ){
		$this->{PageLabel} = $label;
		$this->labelPages( $label );
	}
	$this->setPageMode( $mode ) if( $mode );
	$this->setPageLayout( $layout ) if( $layout );
	$this->setViewerPref( $PDF::root->{Prefs} );
	$this->makeMetaData( ) if( $PDF::root->{Prefs}->{UseMetaData} );
	return $this;
}

%Catalog::roms = (
	'I' => 1,
	'V' => 5,
	'X' => 10,
	'L' => 50,
	'C' => 100,
	'D' => 500,
	'M' => 1000,
);

%Catalog::romandigits = (
	1 => [ 'I', 'V' ],
	10 => [ 'X', 'L' ],
	100 => [ 'C', 'D' ],
	1000 => [ 'M','MMMMM' ],
);

# Not a class method
sub romanToDec {
	my $str = shift;
	my $dec = 0;
	my( $lastdigit, $digit ) = ( undef, undef );
	foreach ( split( //, uc( $str ) ) ){
		$digit = $Catalog::roms{$_};
		if( $lastdigit < $digit ){
			$dec -= $lastdigit;
		} else {
			$dec += $lastdigit;
		}
		$lastdigit = $digit;
	}
	return $dec + $lastdigit;
}

sub decToRoman {
	my $arg = shift;
	if( $arg < 0 || $arg > 5000 ){
		return $arg;
	}
	my( $x, $roman );
	foreach my $d ( 1000, 100, 10, 1 ) {
		my $digit = int( $arg / $d );
		my( $i, $v ) = @{$Catalog::romandigits{$d}};
		if ( !$digit ){
		} elsif( $digit < 4 ){
			$roman .= $i x $digit;
		} elsif( $digit < 5 ){
			$roman .= "$i$v";
		} elsif( $digit < 6 ){
			$roman .= $v;
		} elsif( $digit < 9 ){
			$roman .= $v . $i x ( $digit - 5 );
		} else {
			$roman .= "$i$x";
		}
		$arg -= $digit * $d;
		$x = $i;
	}
	return $roman;
}

sub labelPages {
	my $this = shift;
	my $count = 0;
	$PDF::root->{Prefs}->{PageLabel} = $this->{PageLabel} = shift;
	my @segs = split( /(?<!\\),\s*/, $this->{PageLabel} );
	my $style = undef;
	foreach my $seg ( @segs ){
		my ( $start, $stop ) = split( /(?<!\\)-/, $seg );
		my ( $startnum, $stopnum ) = ( undef, undef );
		# 10/11/2002: Allow empty range setting to specified skipped pages
		if( !$start ){
			$count++;
			next;
		}
		$start =~ s/(\w+)$//;
		$startnum = $1;
		if( $startnum =~ /^\d+$/ ){
			$style = 'D';
		} elsif( $startnum =~ /^[IVXLCDM]+$/ ){
			$style = 'R';
		} elsif( $startnum =~ /^[ivxlcdm]+$/ ){
			$style = 'r';
		} elsif( $startnum !~ /[A-Z]/ ){
			$style = 'a';
		} else {
			$style = 'A';
		}
		# Keys in $thislabel:
		# Count, Style, Orig, Prefix, Size
		my $thislabel = { 'Count' => $count, 'Style' => $style, 'Orig' => $startnum };
		if( length $start ){
			$thislabel->{Prefix} = $start;
		}
		if( $style eq 'r' || $style eq 'R' ){
			$startnum = &romanToDec( $startnum );
		} elsif( $style eq 'a' || $style eq 'A' ){
			$startnum = ord( uc( $startnum ) ) - ord( 'A' ) + 1;
		}
		if( length $stop ){
			$stop =~ /(\w+)$/;
			$stopnum = $1;
			if( $style eq 'r' || $style eq 'R' ){
				$stopnum = &romanToDec( $stopnum );
			} elsif( $style eq 'a' || $style eq 'A' ){
				$stopnum = ord( uc( $stopnum ) ) - ord( 'A' ) + 1;
			}
			for( $startnum..$stopnum ){
				$count++;
			}
			$thislabel->{Size} = $stopnum - $startnum + 1;
		} elsif( $seg !~ /-/ ){
			$count++;
			$thislabel->{Size} = 1;
		} else {
			$count++;
			$thislabel->{Size} = 0;
		}
		$thislabel->{Start} = $startnum;
		push( @{$this->{PageLabels}}, $thislabel );
	}
	$this->rewindPageLabel( );
}

%Catalog::LabelIterator = ( );

sub getNextPageLabel {
	my $this = shift;
	my $p = \%Catalog::LabelIterator;
	# Increment physical page number
	$p->{k}++;
	# If no labels are defined, then just return the number
	if( scalar @{$this->{PageLabels}} == 0 ){
		return $p->{k};
	}
	# If passed last page label and it is not open, then return empty string
	if( $p->{i} == scalar @{$this->{PageLabels}} ){
		return '';
	}
	my $q = $this->{PageLabels}->[ $p->{i} ];
	# $q now points to a hash with these keys: Count, Start, Orig, Style, Size
	if( $p->{k} < $q->{Count} + 1 ){
		return '';
	}
	if( $q->{Size} ){
		my $t;
		if( $q->{Style} eq 'r' ){
			$t = &Catalog::decToRoman( $p->{n} );
		} elsif( $q->{Style} eq 'R' ){
			$t = uc( &Catalog::decToRoman( $p->{n} ) );
		} else {
			$t = $p->{n};
		}
		$p->{n}++;	# Note that $p->{n} can be arabic or alphabetic
		if( $p->{j} < $q->{Size} ){
			$p->{j}++;
			return length( $q->{Prefix} )? "$q->{Prefix} $t": $t;
		} else {
			$p->{i}++;
			$p->{j} = 0;
			if( $p->{i} < scalar @{$this->{PageLabels}} ){
				$q = $this->{PageLabels}->[ $p->{i} ];
				if( $q->{Style} eq 'r' || $q->{Style} eq 'R' ){
					$p->{n} = $q->{Start};
				} else {
					$p->{n} = $q->{Orig};
				}
			}
			$p->{k}--;
			return $this->getNextPageLabel( );
		}
	} else {
		my $t;
		if( $q->{Style} eq 'r' ){
			$t = &Catalog::decToRoman( $p->{n} );
		} elsif( $q->{Style} eq 'R' ){
			$t = uc( &Catalog::decToRoman( $p->{n} ) );
		} else {
			$t = $p->{n};
		}
		$p->{n}++;	# Note that $p->{n} can be arabic or alphabetic
		return length( $q->{Prefix} )? "$q->{Prefix} $t": $t;
	}
}

sub rewindPageLabel {
	my $this = shift;
	my $p = \%Catalog::LabelIterator;
	$p->{i} = 0;
	$p->{j} = 0;
	$p->{k} = 0;
	$p->{n} = 1;
	$p->{t} = '';
	if( scalar @{$this->{PageLabels}} ){
		my $q = $this->{PageLabels}->[0];
		if( $q->{Style} eq 'r' || $q->{Style} eq 'R' ){
			$p->{n} = $q->{Start};
		} else {
			$p->{n} = $q->{Orig};
		}
	}
}

sub appendPages {
	my ( $this, $oPages ) = @_;
	return if( defined $this->{Pages} );	# This is is critical!
	$this->{Pages} = $oPages;
	$this->appendChild( $oPages );
}

sub appendOutlines {
	my ( $this, $oOutlines ) = @_;
	return if( defined $this->{Outlines} );
	$this->{Outlines} = $oOutlines;
	$this->appendChild( $oOutlines );
}

sub appendAcroForm {
	my ( $this, $oAcroForm ) = @_;
	return if( defined $this->{AcroForm} );
	$this->{AcroForm} = $oAcroForm;
	$this->appendChild( $oAcroForm );
}

sub appendMetaData {
	my ( $this, $oMetaData ) = @_;
	return if( defined $this->{MetaData} );
	$this->{MetaData} = $oMetaData;
	$this->appendChild( $oMetaData );
}

%Catalog::AppendMethods = (
	AcroForm => \&Catalog::appendAcroForm,
	Outlines => \&Catalog::appendOutlines,
	Pages => \&Catalog::appendPages,
	MetaData => \&Catalog::appendMetaData,
);

sub add {
	my( $this, $that ) = @_;
	if( exists $Catalog::AppendMethods{ ref( $that ) } ){
		&{$Catalog::AppendMethods{ ref( $that ) }}( $this, $that );
	}
	return $that;
}

sub getPagesRoot {
	return shift->{Pages};
}

sub getOutlinesRoot {
	return shift->{Outlines};
}

sub getAcroForm {
	my $this = shift;
	if( !defined $this->{AcroForm} ){
		my $oldroot = $PDF::root;
		&PDF::choose( $this->{par} );
		$PDF::root->newForm( );
		&PDF::choose( $oldroot ) if( $oldroot );
	}
	return $this->{AcroForm};
}

sub getMetaData {
	return shift->{MetaData};
}

sub makeMetaData {
	my $this = shift;
	my $meta = new MetaData( shift );
	$this->appendMetaData( $meta );
}

sub setViewerPref {
	my( $this, $attr ) = @_;
	for( qw(Toolbar Menubar WindowUI FitWindow CenterWindow DisplayDocTitle) ){
		if( exists $attr->{$_} ){
			$this->{$_} = $attr->{$_};
		}
	}
}

sub setPageMode {
	my( $this, $mode ) = @_;
	if( exists $Catalog::PageModes{$mode} ){
		$mode = $Catalog::PageModes{$mode};
	} else {
		$mode += 0;
	}
	if( $mode > 0 && $mode < 4 ){
		my %modes = reverse %Catalog::PageModes;
		$this->{PageMode} = $modes{$mode};
	}
}

sub setPageLayout {
	my( $this, $layout ) = @_;
	if( exists $Catalog::PageLayouts{$layout} ){
		$layout = $Catalog::Pagelayouts{$layout};
	} else {
		$layout += 0;
	}
	if( $layout > 0 && $layout < 4 ){
		my %layouts = reverse %Catalog::PageLayouts;
		$this->{PageLayout} = $layouts{$layout};
	}
}

# The following three functions are used in a very special and restricted
# case where the entirety of a single file is imported

sub setThreads {
	my( $this, $pobj ) = @_;
	$this->{Threads} = $pobj;
}

sub setNames {
	my( $this, $pobj ) = @_;
	if( defined $this->{Names} && ref $this->{Names} eq 'NamesTree' ){
		$this->{Names}->{par}->deleteChild( $this->{Names} );
		$this->{Names}->finalize( );
	}
	$this->{Names} = $pobj;
}

sub addNamedPage {
	my( $this, $page ) = @_;
	$this->{Names}->addName( 'Pages', $page->{Name}, $page );
}

sub addImportedNamedDest {
	my( $this, $name, $pobj ) = @_;	# $pobj is the NEW PObject. Precondition: ALL pages are imported.
	$this->{Names}->addName( 'Dests', $name, $pobj );
}

# Argument MUST be a Page, PObject, or PArray or PDict (direct data) when used internally.
# Updated 01/14/2003 to take display ratio
sub setOpenAction {
	my( $this, $p, $ratio ) = @_;
	$this->{DefaultPage} = $p;
	$this->{DefaultRatio} = $ratio;
}

# Used publically, argument may be a Page, a page number, or a page name.
# Updated 01/14/2003 to take display ratio
sub setOpenPage {
	my $this = shift;
	$this->setOpenAction( @_ );
}

sub makeCode {
	my $this = shift;
	my @prefix = map { &PDF::escStr(
		$PDF::root->{Encrypt} && defined $_->{Prefix}?
		&PDF::RC4( $this->{EncKey}, $_->{Prefix} ):
		( defined $_->{Prefix}? $_->{Prefix}: '' )
	) } @{$this->{PageLabels}};
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Type /Catalog ',
		qq{/Pages $this->{Pages}->{ObjId} 0 R }
	);
	if( defined $this->{Outlines} ){
		print qq{${PDF::endln}/Outlines $this->{Outlines}->{ObjId} 0 R };
	}
	if( defined $this->{AcroForm} ){
		if( ref( $this->{AcroForm} ) eq 'AcroForm' || ref( $this->{AcroForm} ) eq 'PObject'){
			print qq{${PDF::endln}/AcroForm $this->{AcroForm}->{ObjId} 0 R };
		} else {	# Must be a PDict then
			print qq{${PDF::endln}/AcroForm };
			if( $main::root->{Encrypt} ){
				&PDF::encryptPDF( $this->{AcroForm}, $this->{EncKey} );
				&PDF::printPDF( $this->{AcroForm} );
				&PDF::encryptPDF( $this->{AcroForm}, $this->{EncKey} );
			} else {
				&PDF::printPDF( $this->{AcroForm} );
			}
		}
	}
	if( defined $this->{DefaultPage} ){
		my $ratio = '/Fit';
		if( defined $this->{DefaultRatio} && $this->{DefaultRatio} ){
			if( $this->{DefaultRatio} eq 'FitWidth' ){
				$ratio = "/FitWidth -32768";
			} elsif( $this->{DefaultRatio} + 0 > 0 ){
				$ratio = sprintf( "/XYZ -32768 -32768 %.4f", $this->{DefaultRatio} / 100 );
			}
		}
		if( ref( $this->{DefaultPage} ) eq 'Page' ){
			printf( "${PDF::endln}/OpenAction [%d 0 R $ratio]", $this->{DefaultPage}->getObjId( ) );
		} elsif( ref( $this->{DefaultPage} ) eq 'PObject' ){
			printf( "${PDF::endln}/OpenAction [%d 0 R $ratio]", $this->{DefaultPage}->{ObjId} );
		} elsif( ref $this->{DefaultPage} ){	# PArray or PDict
			print qq{${PDF::endln}/OpenAction };
			if( $main::root->{Encrypt} ){
				&PDF::encryptPDF( $this->{DefaultPage}, $this->{EncKey} );
				&PDF::printPDF( $this->{DefaultPage} );
				&PDF::encryptPDF( $this->{DefaultPage}, $this->{EncKey} );
			} else {
				&PDF::printPDF( $this->{DefaultPage} );
			}
		} elsif( $this->{DefaultPage} =~ /^\d+$/ ){	# Page number
			my $obj = $PDF::root->getPagesRoot->getPageByNumber( $this->{DefaultPage} );
			if( defined $obj ){
				printf( "${PDF::endln}/OpenAction [%d 0 R $ratio]", $obj->getObjId( ) );
			}
		} else {	# Page name
			my $obj = $PDF::root->getObjByName( $this->{DefaultPage} );
			if( defined $obj && ref( $obj ) eq 'Page' ){
				printf( "${PDF::endln}/OpenAction [%d 0 R $ratio]", $obj->getObjId( ) );
			}
		}
	}
	if( defined $this->{MetaData} ){
		print qq{${PDF::endln}/MetaData $this->{MetaData}->{ObjId} 0 R };
	}
	if( defined $this->{Threads} ){
		print qq{${PDF::endln}/Threads $this->{Threads}->{ObjId} 0 R };
	}
	if( defined $this->{Names} ){
		if( ref( $this->{Names} ) eq 'PObject' || ref( $this->{Names} ) eq 'NamesTree' ){
			printf qq{$PDF::endln/Names %d 0 R }, $this->{Names}->getObjId( );
		} elsif( ref( $this->{Names} ) eq 'PDict' ){	# If imported, must be a PDict then
			print qq{${PDF::endln}/Names };
			if( $main::root->{Encrypt} ){
				&PDF::encryptPDF( $this->{Names}, $this->{EncKey} );
				&PDF::printPDF( $this->{Names} );
				&PDF::encryptPDF( $this->{Names}, $this->{EncKey} );
			} else {
				&PDF::printPDF( $this->{Names} );
			}
		}
	}
	if( @{$this->{PageLabels}} ){
		print join( $PDF::endln,
			'',
			'/PageLabels << /Nums [',
		);
		# Page labels MUST have an entry for page 0
		if( $this->{PageLabels}->[0]->{Count} > 0 ){
			print "0 << /S /D /St 1 >> ";
		}
		for my $lb ( @{$this->{PageLabels}} ){
			print join( ' ',
				$lb->{Count},
				'<<',
				qq{/S /$lb->{Style}},
				sprintf( '/P (%s)', shift( @prefix ) ),
				qq{/St $lb->{Start}} x ( defined $lb->{Start} ),
				'>>',
			);
		}
		print $PDF::endln . '] >>';
	}
	print "$PDF::endln/ViewerPreferences << ";
	if( !$this->{Toolbar} ){ print "$PDF::endln/HideToolbar true "; }
	if( !$this->{Menubar} ){ print "$PDF::endln/HideMenubar true "; }
	if( !$this->{WindowUI} ){ print "$PDF::endln/HideWindowUI true "; }
	if( $this->{FitWindow} ){ print "$PDF::endln/FitWindow true "; }
	if( $this->{CenterWindow} ){ print "$PDF::endln/CenterWindow true "; }
	if( $this->{DisplayDocTitle} ){ print "$PDF::endln/DisplayDocTitle true "; }
	print "$PDF::endln>> ";
	print join( $PDF::endln,
		'',
		qq{/PageMode /$this->{PageMode} },
		qq{/PageLayout /$this->{PageLayout} },
		'>> ',
		'endobj',
		''
	);
}

sub startXML {	# To update the default open page only
	my $this = shift;
	return unless( defined $this->{DefaultPage} );
	if( ref( $this->{DefaultPage} ) eq 'Page' ){
		$this->{DefaultPage}->{IsDefault} = 1;
	} elsif( ref( $this->{DefaultPage} ) ){
		return;
	} elsif( $this->{DefaultPage} =~ /^\d+$/ ){	# Page number
		my $obj = $PDF::root->getPagesRoot->getPageByNumber( $this->{DefaultPage} );
		if( defined $obj ){
			$obj->{IsDefault} = 1;
		}
	} else {	# Page name
		my $obj = $PDF::root->getObjByName( $this->{DefaultPage} );
		if( defined $obj && ref( $obj ) eq 'Page' ){
			$obj->{IsDefault} = 1;
		}
	}
}

sub finalize {
	my $this = shift;
	for( qw(Outlines Pages AcroForm Metadata DefaltPage Threads Names) ){
		delete $this->{$_};
	}
}

#===========================================================================#
# PDFEncrypt
#===========================================================================#

package PDFEncrypt;

@ISA = qw(PDFTreeNode);

use bytes;
use strict;

sub new {
	my( $class, $opwd, $upwd, $perms ) = @_;
	my $this = {
		'OwnerPwd' => $opwd,
		'UserPwd' => $upwd,
		'Owner' => &PDF::padPwd( $opwd ),
		'User' => &PDF::padPwd( $upwd ),
		'Perm' => 0xFFFFFFC0,
		'EOwner' => undef,
		'EUser' => undef,
	};
	bless $this, $class;
	$perms->{Print} && do { $this->{Perm} |= 4; };		# Bit 3
	$perms->{Change} && do { $this->{Perm} |= 8; };		# Bit 4
	$perms->{Select} && do { $this->{Perm} |= 16; };	# Bit 5
	$perms->{ChangeAll} && do { $this->{Perm} |= 32; };	# Bit 6
	$PDF::root->{Encrypt} = $this;
	$PDF::root->appendChild( $this );
	if( $PDF::root->{StrongEnc} ){
		$perms->{LockForm} && do { $this->{Perm} ^= 256; };		# Bit 9
		$perms->{NoAccess} && do { $this->{Perm} ^= 512; };		# Bit 10
		$perms->{NoAssembly} && do { $this->{Perm} ^= 1024; };		# Bit 11
		$perms->{PrintAsImage} && do { $this->{Perm} ^= 2048; $this->{Perm} |= 4; };	# Bit 12
	}
	return $this;
}

# Will be used by the writePDF function
sub prepareFile {
	my $this = shift;
	if( $PDF::root->{StrongEnc} ){
		# Algorithm 3.3 Computing the O value
		# 1. Pad or truncate the owner password, or user password if n.a.
		my $temp = ( $this->{OwnerPwd} eq ''? $this->{User}: $this->{Owner} );
		# 2. Pass the result to MD5 function. Loop 50 additional times.
		for( 1..51 ){	# MD5 for 51 times in total
			$temp = PDF::MD5( $temp );
		}
		# 3. Use the first N bytes as the key for RC4.
		my $RCkey = substr( $temp, 0, $PDF::root->{KeyLength} );	# Truncate the key.
		# 4. Pad or truncate the user password.
		# 5. Encrypt the padded user password with RC4. Loop 19 additional times.
		my $input = $this->{User};
		my $output = PDF::RC4( $RCkey, $input );
		my @chars = split( //, $RCkey );
		for my $i ( 1..19 ){
			$input = $output;
			$temp = join( '', map { chr( ord( $_ ) ^ $i ) } @chars );
			$output = PDF::RC4( $temp, $input );
		}
		# 6. The output is the O value
		$this->{EOwner} = $output;
	} else {
		$this->{EOwner} = &PDF::RC4( substr( &PDF::MD5( $this->{OwnerPwd} eq ''?
			$this->{User}: $this->{Owner} ), 0, 5 ), $this->{User} );
	}
	# Algorithm 3.2 Computing the an encryption key
	my $temp = &PDF::MD5(
		$this->{User},				# Pad or truncate the password
		$this->{EOwner},			# Input the O value
		pack( 'V', $this->{Perm} ),	# Input the P value as an unsigned integer
		$PDF::root->{FileID}		# Pass the first element of the file ID
	);
	if( $PDF::root->{StrongEnc} ){	# MD5 for 51 times in total
		for( 1..50 ){ $temp = &PDF::MD5( $temp ); }
	}
	$PDF::root->{EKey} = substr( $temp, 0, ( $PDF::root->{StrongEnc}? $PDF::root->{KeyLength}: 5 ) );
	if( $PDF::root->{StrongEnc} ){
		# Algorithm 3.5 Computing the U value (revision 3)
		# Create encryption key and get MD5 output from the pad chars and the file ID
		my $input = &PDF::MD5( $PDF::PadChars, $PDF::root->{FileID} );
		# Use RC4 to encrypt the 16-byte result; repeat 19 additional times.
		my $output = &PDF::RC4( $PDF::root->{EKey}, $input );
		my @chars = split( //, $PDF::root->{EKey} );
		for my $i ( 1..19 ){
			$input = $output;
			$temp = join( '', map { chr( ord( $_ ) ^ $i ) } @chars );
			$output = &PDF::RC4( $temp, $input );
		}
		$this->{EUser} = $output . ( chr( 0 ) x 16 );
	} else {
		# Algorithm 3.4 Computing the U value (revision 2)
		$this->{EUser} = &PDF::RC4( $PDF::root->{EKey}, $PDF::PadChars );
	}
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Filter /Standard',
		( $PDF::root->{StrongEnc}? '/V 2': '/V 1' ),
		( $PDF::root->{StrongEnc}? '/R 3': '/R 2' ),
		'/Length ' . ( $PDF::root->{KeyLength} * 8 ),
		sprintf( '/P %d', $this->{Perm} - 4294967296 ),
		sprintf( '/O (%s)', PDF::escStr( $this->{EOwner} ) ),
		sprintf( '/U (%s)', PDF::escStr( $this->{EUser} ) ),
		'>> ',
		'endobj',
		'',
	);
}

#===========================================================================#
# Resources dictionary
#===========================================================================#

package Resources;

sub new {
	my $class = shift;
	my $this = {
		XObject => { },
		Shading => { },
		Pattern => { },
		ColorSpace => { },
		ExtGState => { },
		Font => { },
	};
	bless $this, $class;
	if( @_ ){
		$this->merge( shift );
	}
	return $this;
}

sub merge {
	my( $this, $that ) = @_;
	for my $res ( qw(XObject Shading Pattern ColorSpace ExtGState Font) ){
		for( keys %{$that->{$res}} ){
			$this->{$res}->{$_} = 1;
		}
	}
}

#===========================================================================#
# Pages
#===========================================================================#

package Pages;

@Pages::ISA = qw(PDFTreeNode);

%Pages::PageSizes = (
	Letter => [ 612, 792 ],
	LetterR => [ 792, 612 ],
	Legal => [ 612, 1008 ],
	LegalR => [ 1008, 612 ],
	A4 => [ 595, 842 ],
	A4R => [ 842, 595 ],
	A3 => [ 1190, 1684 ],
	A3R => [ 1684, 1190 ],
	B5 => [ 516, 729 ],
	B5R => [ 729, 516 ],
	B4 => [ 1132, 1458 ],
	B4R => [ 1458, 1132 ],
	Env10 => [ 684, 297 ],
	Postcard => [ 432, 288 ],
);

sub new {
	my( $class, $PageBox ) = @_;
	my $size = 'Letter';
	unless( ref( $PageBox ) eq 'Rect' ){	# $PageBox can either be a string or a Rect object.
		$size = $PageBox || $PDF::root->{Prefs}->{PageSize} || 'Letter';
		if( !exists $Pages::PageSizes{$size} ){
			$size = 'Letter';
		}
		$PageBox = new Rect( 0, 0, @{$Pages::PageSizes{$size}} );
	}
	my $this = {
		'MediaBox' => [ 0, 0, $PageBox->width( ), $PageBox->height( ) ],
		'Kids' => [ ],	# Kid can be a Page or PDFTreeNode
		'PageSize' => $size,
		'ProcSet' => { PDF => 1, Text => 1 },
		'Count'	=> 0,	# Always 0 unless set by the top-level Pages (which acts like a factory)
	};
	$PDF::root->{Catalog}->appendPages( $this );
	bless $this, $class;
}

sub appendPage {
	my ( $this, $oPage ) = @_;
	if( !$oPage->{par} ){
		push( @{$this->{Kids}}, $oPage );
		$this->appendChild( $oPage );
	}
	$this->{par}->addNamedPage( $oPage );
	return $oPage;
}

sub appendImportedPage {
	my( $this, $PageObjArray, $fobj, $PageRange ) = @_;
	push( @{$this->{Kids}}, @$PageObjArray );
	for( @$PageObjArray ){
		$_->{Data}->{Parent} = $this;	# NOTE: The PObject MUST remove this linkage to release memory!
	}
	$this->appendChild( new PureXMLNode( 'Import', { File => $fobj->{FileName},
		Pages => join( ', ', @$PageRange ) } ) );
}

# Requires a page number (zero-based), return the Page object
sub getPageByNumber {
	my( $this, $pg ) = @_;
	if( $pg >= @{$this->{Kids}} ){ return undef; }
	return $this->{Kids}->[ $pg ];
}

sub reorganizePages {
	my( $this, @seq ) = @_;
	@{$this->{Kids}} = @{$this->{Kids}}[ @seq ];
}

# For background-compatibility only
sub appendFont { my ( $this, $obj ) = @_; return $this->add( $obj ); }
sub appendImage { my ( $this, $obj ) = @_; return $this->add( $obj ); }
sub appendXObject { my ( $this, $obj ) = @_; return $this->add( $obj ); }
sub appendShading { my ( $this, $obj ) = @_; return $this->add( $obj ); }
sub appendPattern { my ( $this, $obj ) = @_; return $this->add( $obj ); }
sub appendColorSpace { my ( $this, $obj ) = @_; return $this->add( $obj ); }
sub appendGState { my ( $this, $obj ) = @_; return $this->add( $obj ); }

sub add {
	my( $this, $that ) = @_;
	if( defined $that->{par} && $that->{par} ){
		$that->{par}->deleteChild( $that );
	}
	$this->appendChild( $that );
	return $that;
}

sub setProcSet {
	my( $this, @proc ) = @_;
	map{
		$this->{ProcSet}->{$_} = 1;
	} @proc;
}

sub getProcSet {
	my $this = shift;
	return keys %{$this->{ProcSet}};
}

sub swapPage {
	my( $this, $p, $q ) = @_;
	return if( ref( $q ) ne ref( $p ) || $p == $q || $p->{par} != $this || $q->{par} != $this );
	my( $foundthis, $foundthat ) = ( 0, 0 );
	for( @{$this->{Kids}} ){
		$_ == $p && do { ++$foundthis; $_ = $q; last if( $foundthat ); next };
		$_ == $q && do { ++$foundthat; $_ = $p; last if( $foundthis ); next };
	}
	my( $thisprev, $thisnext, $thatprev, $thatnext ) = ( $p->{prev}, $p->{next}, $q->{prev}, $q->{next} );
	$this->deleteChild( $p );
	$this->deleteChild( $q );
	if( $thisprev && $thisprev != $q ){
		$thisprev->appendSibling( $q );
	} elsif( $thisnext && $thisnext != $q ){
		$thisnext->prependSibling( $q );
	} else {
		$this->appendChild( $q );
	}
	if( $thatprev && $thatprev != $p ){
		$thatprev->appendSibling( $p );
	} elsif( $thatnext && $thatnext != $p ){
		$thatnext->prependSibling( $p );
	} else {
		$this->appendChild( $p );
	}
}

sub findParent {
	my( $this, $page ) = @_;
	if( exists $this->{PageParentID}->{ $page } ){
		return $this->{PageParentID}->{ $page };
	} else {
		return $this->{ObjId};
	}
}

sub makeCode {
	my $this = shift;
	# If it has >10 kids, then create temporary Pages nodes and do the partitioning.
	# The constructor is called, but the nodes are not linked to the document object tree.
	# After code output is done, all these nodes are removed.
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Type /Pages ',
		'',
	);
	%{$this->{ParentID}} = ( );
	if( scalar @{$this->{Kids}} > 10 ){
		my @kids = @{$this->{Kids}};
		while( scalar @kids > 10 ){
			my @upper = ( );
			while( scalar @kids ){
				my $node = new Pages( );
				@{$node->{Kids}} = splice( @kids, 0, 10 );
				$node->{Count} = 0;
				$node->{ObjId} = ++$PDF::root->{ObjectID};
				$node->{GenId} = 0;
				for my $p ( @{$node->{Kids}} ){
					$this->{PageParentID}->{ $p } = $node->{ObjId};
					if( ref( $p ) eq 'Pages' ){
						$node->{Count} += $p->{Count};
						$node->appendChild( $p );
					} elsif( ref( $p ) eq 'PObject' ){	# Imported page
						$p->{Data}->{Parent} = bless {
							'ObjId' => $node->{ObjId},
							'GenId' => 0,
						}, 'PRef';	# Associate the page with the new Pages object
						$node->{Count}++;
					} else {
						$node->{Count}++;
					}
				}
				push( @upper, $node );
			}
			@kids = @upper;
		}
		for( @kids ){
			$this->appendChild( $_ ) if( ref( $_ ) eq 'Pages' );
		}
		print join( $PDF::endln,
			qq{/Count } . ( scalar @{$this->{Kids}} ) . ' ',
			'/Kids [ ' . join( ' ', map{
				$_->getObjId( ) . ' 0 R'
			} @kids ) . ' ] ',
			'',
		);
	} else {
		print join( $PDF::endln,
			qq{/Count } . ( $this->{Count} || scalar @{$this->{Kids}} ) . ' ',
			'/Kids [ ' . join( ' ', map{ 
				$_->getObjId( ) . ' 0 R'
			} @{$this->{Kids}} ) . ' ] ',
			'',
		);
	}
	if( ref( $this->{par} ) ne 'Catalog' ){	# If not root Pages node
		print sprintf( "/Parent %d 0 R $PDF::endln", $this->{par}->{ObjId} );
	}
	print join( $PDF::endln,
		'>> ',
		'endobj',
		''
	);
}

sub cleanUp {
	my $this = shift;
	my $node = $this->{last};
	while( $node ){
		my $prev = $node->{prev};
		if( ref( $node ) eq 'Pages' ){
			$this->deleteChild( $node );
		}
		$node = $prev;
	}
	%{$this->{ParentID}} = ( );
}

sub finalize {
	my $this = shift;
	for my $p ( @{$this->{Kids}} ){
		if( ref( $p ) eq 'PObject' ){
			delete $p->{Data}->{Parent};
		}
	}
	@{$this->{Kids}} = ( );
}

#===========================================================================#
# Color
#===========================================================================#

package Color;

%Color::NamedColors = (
	'ANTIQUEWHITE'	=> 'FAEBD7', 
	'AQUA'			=> '00FFFF', 
	'AQUAMARINE'	=> '7FFFD4', 
	'AZURE'			=> 'F0FFFF', 
	'BEIGE'			=> 'F5F5DC', 
	'BISQUE'		=> 'FFE4C4', 
	'BLACK'			=> '000000', 
	'BLANCHEDALMOND'=> 'FFEBCD', 
	'BLUE'			=> '0000FF', 
	'BLUEVIOLET'	=> '8A2BE2', 
	'BROWN'			=> 'A52A2A', 
	'BURLYWOOD'		=> 'DEB887', 
	'CADETBLUE'		=> '5F9EA0', 
	'CHARTREUSE'	=> '7FFF00', 
	'CHOCOLATE'		=> 'D2691E', 
	'CORAL'			=> 'FF7F50', 
	'CORNFLOWERBLUE'=> '6495ED', 
	'CORNSILK'		=> 'FFF8DC', 
	'CRIMSON'		=> 'DC143C', 
	'CYAN'			=> '00FFFF', 
	'DARKBLUE'		=> '00008B', 
	'DARKCYAN'		=> '008B8B', 
	'DARKGOLDENROD'	=> 'B8860B', 
	'DARKGRAY'		=> 'A9A9A9', 
	'DARKGREY'		=> 'A9A9A9', 
	'DARKGREEN'		=> '006400', 
	'DARKKHAKI'		=> 'BDB76B', 
	'DARKMAGENTA'	=> '8B008B', 
	'DARKOLIVEGREEN'=> '556B2F', 
	'DARKORANGE'	=> 'FF8C00', 
	'DARKORCHID'	=> '9932CC', 
	'DARKRED'		=> '8B0000', 
	'DARKSALMON'	=> 'E9967A', 
	'DARKSEAGREEN'	=> '8FBC8F', 
	'DARKSLATEBLUE'	=> '483D8B', 
	'DARKSLATEGRAY'	=> '2F4F4F', 
	'DARKSLATEGREY'	=> '2F4F4F', 
	'DARKTURQUOISE'	=> '00CED1', 
	'DARKVIOLET'	=> '9400D3', 
	'DEEPPINK'		=> 'FF1493', 
	'DEEPSKYBLUE'	=> '00BFFF', 
	'DIMGRAY'		=> '696969', 
	'DIMGREY'		=> '696969', 
	'DODGERBLUE'	=> '1E90FF', 
	'FIREBRICK'		=> 'B22222', 
	'FLORALWHITE'	=> 'FFFAF0', 
	'FORESTGREEN'	=> '228B22', 
	'FUCHSIA'		=> 'FF00FF', 
	'GAINSBORO'		=> 'DCDCDC', 
	'GHOSTWHITE'	=> 'F8F8FF', 
	'GOLD'			=> 'FFD700', 
	'GOLDENROD'		=> 'DAA520', 
	'GRAY'			=> '808080', 
	'GREY'			=> '808080', 
	'GREEN'			=> '008000', 
	'GREENYELLOW'	=> 'ADFF2F', 
	'HONEYDEW'		=> 'F0FFF0', 
	'HOTPINK'		=> 'FF69B4', 
	'INDIANRED'		=> 'CD5C5C', 
	'INDIGO'		=> '4B0082', 
	'IVORY'			=> 'FFFFF0', 
	'KHAKI'			=> 'F0E68C', 
	'LAVENDER'		=> 'E6E6FA', 
	'LAVENDERBLUSH'	=> 'FFF0F5', 
	'LAWNGREEN'		=> '7CFC00', 
	'LEMONCHIFFON'	=> 'FFFACD', 
	'LIGHTBLUE'		=> 'ADD8E6', 
	'LIGHTCORAL'	=> 'F08080', 
	'LIGHTCYAN'		=> 'E0FFFF', 
	'LIGHTGOLDENRODYELLOW'	=> 'FAFAD2', 
	'LIGHTGREEN'	=> '90EE90', 
	'LIGHTGRAY'		=> 'D3D3D3', 
	'LIGHTGREY'		=> 'D3D3D3', 
	'LIGHTPINK'		=> 'FFB6C1', 
	'LIGHTSALMON'	=> 'FFA07A', 
	'LIGHTSEAGREEN'	=> '20B2AA', 
	'LIGHTSKYBLUE'	=> '87CEFA', 
	'LIGHTSLATEGRAY'=> '778899', 
	'LIGHTSLATEGREY'=> '778899', 
	'LIGHTSTEELBLUE'=> 'B0C4DE', 
	'LIGHTYELLOW'	=> 'FFFFE0', 
	'LIME'			=> '00FF00', 
	'LIMEGREEN'		=> '32CD32', 
	'LINEN'			=> 'FAF0E6', 
	'MAGENTA'		=> 'FF00FF', 
	'MAROON'		=> '800000', 
	'MEDIUMAQUAMARINE'	=> '66CDAA', 
	'MEDIUMBLUE'	=> '0000CD', 
	'MEDIUMORCHID'	=> 'BA55D3', 
	'MEDIUMPURPLE'	=> '9370DB', 
	'MEDIUMSEAGREEN'=> '3CB371', 
	'MEDIUMSLATEBLUE'	=> '7B68EE', 
	'MEDIUMSPRINGGREEN'	=> '00FA9A', 
	'MEDIUMTURQUOISE'	=> '48D1CC', 
	'MEDIUMVIOLETRED'	=> 'C71585', 
	'MIDNIGHTBLUE'		=> '191970', 
	'MINTCREAM'		=> 'F5FFFA', 
	'MISTYROSE'		=> 'FFE4E1', 
	'MOCCASIN'		=> 'FFE4B5', 
	'NAVAJOWHITE'	=> 'FFDEAD', 
	'NAVY'			=> '000080', 
	'OLDLACE'		=> 'FDF5E6', 
	'OLIVE'			=> '808000', 
	'OLIVEDRAB'		=> '6B8E23', 
	'ORANGE'		=> 'FFA500', 
	'ORANGERED'		=> 'FF4500', 
	'ORCHID'		=> 'DA70D6', 
	'PALEGOLDENROD'	=> 'EEE8AA', 
	'PALEGREEN'		=> '98FB98', 
	'PALETURQUOISE'	=> 'AFEEEE', 
	'PALEVIOLETRED'	=> 'DB7093', 
	'PAPAYAWHIP'	=> 'FFEFD5', 
	'PEACHPUFF'		=> 'FFDAB9', 
	'PERU'			=> 'CD853F', 
	'PINK'			=> 'FFC0CB', 
	'PLUM'			=> 'DDA0DD', 
	'POWDERBLUE'	=> 'B0E0E6', 
	'PURPLE'		=> '800080', 
	'RED'			=> 'FF0000', 
	'ROSYBROWN'		=> 'BC8F8F', 
	'ROYALBLUE'		=> '4169E1', 
	'SADDLEBROWN'	=> '8B4513', 
	'SALMON'		=> 'FA8072', 
	'SANDYBROWN'	=> 'F4A460', 
	'SEAGREEN'		=> '2E8B57', 
	'SEASHELL'		=> 'FFF5EE', 
	'SIENNA'		=> 'A0522D', 
	'SILVER'		=> 'C0C0C0', 
	'SKYBLUE'		=> '87CEEB', 
	'SLATEBLUE'		=> '6A5ACD', 
	'SLATEGRAY'		=> '708090', 
	'SLATEGREY'		=> '708090', 
	'SNOW'			=> 'FFFAFA', 
	'SPRINGGREEN'	=> '00FF7F', 
	'STEELBLUE'		=> '4682B4', 
	'TAN'			=> 'D2B48C', 
	'TEAL'			=> '008080', 
	'THISTLE'		=> 'D8BFD8', 
	'TOMATO'		=> 'FF6347', 
	'TURQUOISE'		=> '40E0D0', 
	'VIOLET'		=> 'EE82EE', 
	'WHEAT'			=> 'F5DEB3', 
	'WHITE'			=> 'FFFFFF', 
	'WHITESMOKE'	=> 'F5F5F5', 
	'YELLOW'		=> 'FFFF00', 
	'YELLOWGREEN'	=> '9ACD32', 
);

# For the following conversion functions, arguments are in the range of 0 thru 1, decimal forms only.
# RGB -> CMYK        | CMYK -> RGB
# K=min(1-R,1-G,1-B) | R=1-min(1,C*(1-K)+K)
# C=(1-R-K)/(1-K)    | G=1-min(1,M*(1-K)+K)
# M=(1-G-K)/(1-K)    | B=1-min(1,Y*(1-K)+K)
# Y=(1-B-K)/(1-K)    |

sub cmykToRgb {
	my( $c, $m, $y, $k ) = @_;
	my $r = 1 - &PDF::min( 1, $c * ( 1 - $k ) + $k );
	my $g = 1 - &PDF::min( 1, $m * ( 1 - $k ) + $k );
	my $b = 1 - &PDF::min( 1, $y * ( 1 - $k ) + $k );
	return map{ sprintf( "%.4f", $_ ) } ( $r, $g, $b );
}

sub rgbToCmyk {
	my( $r, $g, $b ) = @_;
	my $k = &PDF::min( 1 - $r, 1 - $g, 1 - $b );
	if( $k != 1 ){
		my $c = ( 1 - $r - $k ) / ( 1 - $k );
		my $m = ( 1 - $g - $k ) / ( 1 - $k );
		my $y = ( 1 - $b - $k ) / ( 1 - $k );
		return map{ sprintf( "%.4f", $_ ) } ( $c, $m, $y, $k );
	} else {
		return ( 0, 0, 0, 1 );
	}
}

sub cmykToGray {
	my( $c, $m, $y, $k ) = @_;
	return Color::rgbToGray( Color::cmykToRgb( $c, $m, $y, $k ) );
}

sub grayToCmyk {
	my $g = shift;
	return ( 0, 0, 0, sprintf( "%.4f", 1 - $g ) );
}

sub rgbToGray {
	my( $r, $g, $b ) = @_;
	return sprintf( "%.4f", 0.2125 * $r + 0.7154 * $g + 0.0721 * $b );
}

sub grayToRgb {
	my $g = sprintf( "%.4f", shift );
	return ( $g, $g, $g );
}

# Darken a color in RGB mode, return the RRGGBB form
sub darken {
	my( $color, $ratio ) = @_;
	my @rgb = &Color::tellColor( $color, 'RGB' );
	for( @rgb ){
		if( $ratio <= 1 && $ratio > 0 ){
			$_ = unpack( 'H*', chr( int( $_ * 255 * ( 1 - $ratio ) ) ) );
		}
	}
	return join( '', @rgb );
}

# Lighten a color in RGB mode, return the RRGGBB form
sub lighten {
	my( $color, $ratio ) = @_;
	my @rgb = &Color::tellColor( $color, 'RGB' );
	for( @rgb ){
		if( $ratio <= 1 && $ratio > 0 ){
			$_ = unpack( 'H*', chr( int( ( $_ + ( 1 - $_ ) * $ratio ) * 255 ) ) );
		}
	}
	return join( '', @rgb );
}

# Invert a color in RGB mode, return the RRGGBB form
sub invert {
	my $color = shift;
	my @rgb = &Color::tellColor( $color, 'RGB' );
	for( @rgb ){
		$_ = unpack( 'H*', chr( int( ( 1 - $_ ) * 255 ) ) );
	}
	return join( '', @rgb );
}

# Return the RRGGBB form from r, g, and b components
sub rgb {
	my( $r, $g, $b ) = @_;
	return unpack( 'H*', join( '', chr( $r ), chr( $g ), chr( $b ) ) );
}

# Return a list of values in the range between 0 and 1 (1, 3, or 4 values)
# Input could be:
# 1. A color value in hex form (leading '#' optional): 6699CC, 3F, 2010D400
# 2. A color name, predefined or custom: DeepSkyBlue, MyBgColor
# 3. A list of values in the range between 0 and 1, separated by commas
sub tellColor {
	my( $color, $space ) = @_;
	$space ||= $PDF::root->{Prefs}->{ColorSpace} || "RGB";
	$color ||= '000000';
	if( $space ne 'RGB' && $space ne 'CMYK' && $space ne 'Gray' ){
		&PDF::PDFError( 'tellColor', "Color space must be RGB, CMYK, or Gray." );
	}
	my @comp = split( /,\s*/, $color );	# Try case 3 first
	if( !@comp ){
		$color = $comp[0] = '000000';
	}
	if( @comp == 1 ){	# Could be case 1, 2, or 3
		$color = uc( $color );
		if( $color =~ /^\#?[A-F0-9]{2,}$/ ){	# Case 1
			$color =~ s/(..)/pack("c", hex($1))/ge;
			@comp = map{ sprintf( "%.4f", ord($_)/255.0 ) } ( split( //, $color ) );
		} elsif( exists $Color::NamedColors{$color} ){	# Case 2: Predefined color names
			$color = $Color::NamedColors{$color};
			$color =~ s/(..)/pack("c", hex($1))/ge;
			@comp = map{ sprintf( "%.4f", ord($_)/255.0 ) } ( split( //, $color ) );
		} elsif( exists $PDF::root->{CustomColors}->{$color} ){	# Case 2: Custome color names
			@comp = @{$PDF::root->{CustomColors}->{$color}->{$space}};
		}
	}
	for( @comp ){
		$_ += 0;
		if( $_ > 1 || $_ < 0 ){
			&PDF::PDFError( 'tellColor', "Incorrect color value: $color." );
		}
	}
	if( @comp > 1 ){	# Case 3: rgb or cmyk; Case 1: RRGGBB or CCMMYYKK
		if( @comp == 3 ){
			if( $space eq 'CMYK' ){
				return &Color::rgbToCmyk( @comp );
			} elsif( $space eq 'RGB' ){
				return @comp;
			} elsif( $space eq 'Gray' ){
				return &Color::rgbToGray( @comp );
			}
		} elsif( @comp == 4 ){
			if( $space eq 'CMYK' ){
				return @comp;
			} elsif( $space eq 'RGB' ){
				return &Color::cmykToRgb( @comp );
			} elsif( $space eq 'Gray' ){
				return &Color::cmykToGray( @comp );
			}
		} else {
			&PDF::PDFError( 'tellColor', join( ', ', "Incorrect number of components for $color: ", @comp ) );
		}
	}
	# At this stage, the only element in @comp stores one decimal value
	if( $space eq 'CMYK' ){
		return &Color::grayToCmyk( $comp[0] );
	} elsif( $space eq 'RGB' ){
		return &Color::grayToRgb( $comp[0] );
	} elsif( $space eq 'Gray' ){
		return $comp[0];
	}
}

#===========================================================================#
# ExtGState
#===========================================================================#

package ExtGState;

@ExtGState::ISA = qw(PDFTreeNode);

%ExtGState::BlendModes = map { $_ => 1} qw(Compatible Normal Multiply Screen Difference Darken Lighten ColorDodge ColorBurn Exclusion HardLight Overlay SoftLight Luminosity Hue Saturation Color);

sub new {
	my( $class ) = @_;
	my $this = {
		'Name' => '',
		'BM' => undef,
		'Alpha' => undef,
	};
	bless $this, $class;
	$this->setName( );
	$PDF::root->getPagesRoot( )->add( $this );
	return $this;
}

sub setBlendMode {
	my( $this, $mode ) = @_;
	if( defined $ExtGState::BlendModes{$mode} ){
		$this->{BM} = $mode;
	}
}

sub setOpacity {
	my( $this, $alpha ) = @_;
	if( $alpha < 0 ){
		$alpha = 0;
	} elsif( $alpha > 1 ){
		$alpha = 1;
	}
	$this->{Alpha} = $alpha;
}

sub makeCode {
	my $this = shift;
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		'/Type /ExtGState',
	);
	if( defined $this->{BM} ){
		print $PDF::endln . qq{/BM /$this->{BM}};
	}
	if( defined $this->{Alpha} ){
		print $PDF::endln . qq{/CA $this->{Alpha} /ca $this->{Alpha}};
	}
	print join( $PDF::endln,
		'',
		'/AIS false ',
		'>> ',
		'endobj',
		''
	);
}

#===========================================================================#
# TableGrid
#===========================================================================#

package TableGrid;

use Carp;

sub new {
	my( $class, $cols, $rows, $list ) = @_;
	bless {
		'Cols' => $cols,	# Number of cells per row
		'Rows' => $rows,	# Number of rows
		'Cells' => $list,	# List of Rect objects, anonymous array
	}, $class;
}

# Get a Rect that may span over multiple cells
sub getCell {
	my( $this, $row, $col, $rowspan, $colspan ) = @_;	# 1-based
	$colspan ||= 1;
	$rowspan ||= 1;
	croak "Table undefined" if( !@{$this->{Cells}} );
	my $idx1 = ( $row - 1 ) * $this->{Cols} + $col - 1;
	my $idx2 = ( $row + $rowspan - 2 ) * $this->{Cols} + $col + $colspan - 2;
	croak "Cell out of boundaries" if( $idx1 > $this->{Cols} * $this->{Rows} - 1
		|| $idx2 > $this->{Cols} * $this->{Rows} - 1 );
	if( $idx1 == $idx2 ){
		return $this->{Cells}->[ $idx1 ];
	} else {
		return $this->{Cells}->[ $idx1 ]->union( $this->{Cells}->[ $idx2 ] );
	}
}

#===========================================================================#
# PDFDoc
#===========================================================================#

package PDFDoc;

@PDFDoc::ISA = qw(PDFTreeNode);
%PDFDoc::TemplateModules = map { $_ => 1 } qw(FloatingText GraphContent PreformText TextContent);

use strict;
use Carp;
use Outlines;
use PDFFile;
use XML::Parser;
use FileHandle;
use File::Copy;
use Page;
use Annot;
use GraphContent;
use ImageContent;
use XObject;
use PDFShading;
use PDFTexture;
use Field;
use AcroForm;
use FloatingText;
use PreformText;

$PDFDoc::TempFile = join( '', 'PEV', substr( unpack( 'H*', &PDF::MD5( time( ), rand( ) ) ), 0, 8 ), '.TMP' );
$PDFDoc::FileHandle = new FileHandle;
open( $PDFDoc::FileHandle, "+>$PDF::TempDir/$PDFDoc::TempFile" ) or die "Can't open file $PDFDoc::TempFile for output";
defined $PDFDoc::FileHandle or confess "Can't open temporary file";
binmode( $PDFDoc::FileHandle );
truncate( $PDFDoc::FileHandle, 0 );

END {
	close $PDFDoc::FileHandle;
	undef $PDFDoc::FileHandle;
	unlink "$PDF::TempDir/$PDFDoc::TempFile";
}

sub new {
	my( $class, $attr ) = @_;
	my $this = {
		'Version' => 1.4,		# Not used yet
		'ObjectID' => 0,		# Will be used when exporting PDF code
		'Catalog' => 0,
		'DocInfo' => 0,
		'CurrPage' => 0,		# Reference to current Page object
		'Encrypt' => 0,
		'EKey' => undef,
		'FileID' => undef,
		'Template' => [{}],		# Keyed by object references
		'ImportedFiles' => { },	# Keyed by a PDF File name(!), value is a hash ref of original PObject => copy
		'Prefs' => { },			# Preference settings to replace the old %PDF::fields.
		'ObjectById' => [ ],	# Object by ID
		'XrefTable' => [ ],		# Xref table entries
		'AddXML' => [ ],		# Additional XML codes
		'NameLookupTable' => [{}],
		'CurrOffset' => 0,		# Current offset in temp file used when writing output
		'dep' => 0,				# Used when traversing the object tree (current level)
		'ObjName' => 'N000',	# Used to set names for objects
		'ExcludedPObjs' => { },	# Sometimes some imported PObjects are not referred and should be excluded
		'Fonts'	=> { },			# Fonts used in this document
		'CustomColors' => { },	# Custom color names and values
		'Tables' => [ ],		# List of tables
		'StrongEnc' => 0,		# 1 or 0; use strong encryption
		'KeyLength' => 16,		# Length of key when using strong encryption but seems it MUST be 16
		'TplResources' => { '' => { } },	# Key: template name, value: hash (key: resource object name, value: 1)
		'LastImportPageName' => 'IMP00001',	# Name for last imported page
		'LayerIds' => { },		# Key: layer id; value: layer's XML object (stream) -- for internal use only
	};
	bless $this, $class;
	PDF::choose( $this );
	if( defined $attr && ref( $attr ) eq 'HASH' ){
		for( keys %$attr ){
			$this->{Prefs}->{$_} = $attr->{$_};
		}
		$this->{DocInfo} = new DocInfo( $attr );
		for( qw(PageMode PageLayout PageLabel) ){
			if( !exists $attr->{$_} ){
				$attr->{$_} = '';
			}
		}
		new Catalog(
			$attr->{PageMode}, $attr->{PageLayout}, $attr->{PageLabel}
		);
	} else {
		new DocInfo( );
		new Catalog( );
	}
	if( defined $attr && ref( $attr ) eq 'Rect' ){
		new Pages( $attr );
	} elsif( defined $attr && ref( $attr ) eq 'HASH' ){
		if( exists $attr->{Box} && ref( $attr->{Box} ) eq 'Rect' ){
			new Pages( $attr->{Box} );
		} elsif( exists $attr->{PageSize} ){
			new Pages( $attr->{PageSize} );
		} else {
			new Pages( );
		}
	} else {
		new Pages( $attr );
	}
	new Outlines( );
	if( ref( $attr ) eq 'HASH' &&
		( exists $attr->{OwnerPwd} || exists $attr->{UserPwd} ) ){
		if( exists $attr->{StrongEnc} && $attr->{StrongEnc} == 1 ){
			$this->{StrongEnc} = 1;
		}
		new PDFEncrypt( $attr->{OwnerPwd}, $attr->{UserPwd}, $attr );
	}
	return $this;
}

# Needs a class name as the argument. Recursive.
# Returns a list of objects of the same type.
sub all {
	my $this = shift;
	my $type = shift;
	my $node = shift || $this;
	my @objs = ( );
	push( @objs, $node ) if( ref( $node ) eq $type );
	my $ptr = $node->{son};
	if( $ptr ){
		while( $ptr ){
			push( @objs, $this->all( $type, $ptr ) );
			$ptr = $ptr->{next};
		}
	}
	if( wantarray ){
		return @objs;
	} else {
		my %objs = map{ $_->{Name} => $_ } @objs;
		return \%objs;
	}
};

# Returns a unique name. Need a tentative name to start with.
# Only this method can be called in other modules; not the getName and putName.
sub setName {
	my( $this, $obj, $name ) = @_;
	if( !defined $name || $name !~ /^\w[\w\.\d]+/ ){
		do {
			$name = $this->{ObjName}++;
		} while( exists $this->{NameLookupTable}->[0]->{$name} );
	} else {
		while( exists $this->{NameLookupTable}->[0]->{$name} ){
			$name++;
		}
	}
	push( @{$this->{NameLookupTable}}, $obj );
	$this->{NameLookupTable}->[0]->{$name} = @{$this->{NameLookupTable}} - 1;
	$obj->{Name} = $name;
	return $name;
}

# Retrieve an object by name
sub getObjByName {
	my( $this, $name ) = @_;
	return undef unless exists $this->{NameLookupTable}->[0]->{$name};
	return $this->{NameLookupTable}->[ $this->{NameLookupTable}->[0]->{$name} ];
}

sub getCurrPage {
	return shift->{CurrPage};
}

sub setCurrPage {
	my( $this, $page ) = @_;
	if( $page->isa( 'Page' ) ){
		$this->{CurrPage} = $page;
	}
}

sub getPageCount {
	my $this = shift;
	return scalar @{$this->getPagesRoot( )->{Kids}};
}

sub checkTplRes {
	my( $this, $tplname, $resname ) = @_;
	if( !exists $this->{TplResources}->{ $tplname } ){
		$this->{TplResources}->{ $tplname } = { $resname => 1 };
		return 0;
	}
	if( !exists $this->{TplResources}->{ $tplname }->{ $resname } ){
		$this->{TplResources}->{ $tplname }->{ $resname } = 1;
		return 0;
	}
	return 1;
}

sub importFromFile {
	my( $this, $file ) = @_;
	my $fobj = new PDFFile( $file );
	if( !defined $fobj ){
		croak "Can't import file $file";
	}
	my $bk = $fobj->getTitle( );
	if( $bk =~ /^\s*$/s ){
		$bk = $file;
	}
	my $pg = $this->getPageCount( );
	$this->importPages( $fobj, 0 .. ( $fobj->analyzePages( ) - 1 ) );
	my $sect = new Outlines( $bk, { Page => $pg } );
	for( $fobj->getOutlineItems( ) ){
		$sect->appendEntry( $this->importOutlinesSubtree( $_ ) );
	}
}

# Import a list of pages from a given PDFFile object. Page numbers start at 0.
sub importPages {
	my( $this, $fobj, @PageNums ) = @_;
	return if( ref( $fobj ) ne 'PDFFile' );
#	if( $this->{Encrypt} ){
#		croak "Can't import file while using encryption";
#	}
	if( !exists $this->{ImportedFiles}->{$fobj->{FileName}} ){
		$this->{ImportedFiles}->{$fobj->{FileName}} = { };
	}
	my( $PageObjArray, $CopiedObjects ) = $fobj->copyPages(
		$this->{ImportedFiles}->{$fobj->{FileName}}, @PageNums
	);
	# $this->{ImportedFiles}->{$fobj->{FileName}} has been updated by copyPages
	# Also note @$CopiedObjects are the newly copied objects only.
	$this->{Catalog}->{Pages}->appendImportedPage( $PageObjArray, $fobj, [ @PageNums ] );
	return @$PageObjArray;
}

sub nameImportedPages {
	my( $this, $arrayref ) = @_;
	my @names = ( );
	for( @$arrayref ){
		$_->{Name} = $this->{LastImportPageName};
		push( @names, $this->{LastImportPageName}++ );
		$this->{Catalog}->addNamedPage( $_ );
	}
	return @names;
}

sub getCatalog {
	return shift->{Catalog};
}

sub getDocInfo {
	return shift->{DocInfo};
}

sub getPagesRoot {
	my $this = shift;
	return $this->{Catalog}? $this->{Catalog}->getPagesRoot( ): undef;
}

sub getOutlinesRoot {
	my $this = shift;
	return $this->{Catalog}? $this->{Catalog}->getOutlinesRoot( ): undef;
}

sub getAcroForm {
	my $this = shift;
	return $this->{Catalog}? $this->{Catalog}->getAcroForm( ): undef;
}

sub setSecurity {
	my $this = shift;
	my $attr = shift;
	$this->removeSecurity( ) if( $this->{Encrypt} );
	for( keys %$attr ){
		$this->{Prefs}->{$_} = $attr->{$_};
	}
	if( exists $attr->{StrongEnc} && $attr->{StrongEnc} ){
		$this->{StrongEnc} = 1;
	}
	new PDFEncrypt( $attr->{OwnerPwd}, $attr->{UserPwd}, $attr );
}

sub removeSecurity {
	my $this = shift;
	if( $this->{Encrypt} ){
		$this->deleteChild( $this->{Encrypt} );
		$this->{Encrypt} = 0;
	}
	undef $this->{EKey};
	for( qw(StrongEnc Print Select Change ChangeAll LockForm PrintAsImage NoAccess NoAssembly) ){
		delete $this->{Prefs}->{$_} if exists $this->{Prefs}->{$_};
	}
	$this->{StrongEnc} = 0;
}

sub addXML {
	my( $this, $xml ) = @_;
	push( @{$this->{AddXML}}, $xml );
}

# Assign object IDs before printing out PDF code.
# Must initiate $this->{ObjectID} before calling this function.
sub assignObjectIds {
	my $this = shift;
	my $node = shift;
	if( !defined $node ){
		$node = $this;
		for( @{$this->{ObjectById}} ){
			next unless defined( $_ );
			$_->{ObjId} = 0;
		}
		@{$this->{ObjectById}} = ( );
	} elsif( !$node->{ObjId} ){
		return if( ref $node eq 'PureXMLNode' );	# Would be extend to also skip other types.
		$node->{ObjId} = ++$this->{ObjectID};
		$node->{GenId} = 0;	# This is mandatory; the imported PObjects may need it.
		$this->{ObjectById}->[ $node->{ObjId} ] = $node;
	}
	$node = $node->{son};
	while( $node ){
		$this->assignObjectIds( $node );
		$node = $node->{next};
	}
}

# Assign IDs for IMPORTED objects before printing out PDF code.
# Must initiate $this->{ObjectID} before calling this function.
sub assignImportedObjectIds {
	my $this = shift;
	for my $hashref ( values %{$this->{ImportedFiles}} ){
		for my $pobj ( values %$hashref ){
			$pobj->{ObjId} = ++$this->{ObjectID};
			$this->{ObjectById}->[ $pobj->{ObjId} ] = $pobj;
		}
	}
}

sub printTree {
	my $this = shift;
	my $node = shift;
	$this->{CurrOffset} = tell( $this->{FileHandle} );
	if( defined $node ){
		return if( !$node->{ObjId} );
		$this->{XrefTable}->[ $node->{ObjId} ] =
			sprintf( "%010d 00000 n\x0D\x0A", $this->{CurrOffset} );
		if( $this->{Encrypt} ){
			# Note: although objects acting as delegates use the id as returned by getObjId( ),
			# and a generation id of 1 is used, the following code doesn't matter, since they do not generate code at all.
			$node->{EncKey} = substr(
				&PDF::MD5(
					$this->{EKey},
					substr( pack( 'V', $node->{ObjId} ), 0, 3 ),
					substr( pack( 'V', 0 ), 0, 2 ),
				), 0, ( $this->{StrongEnc}? PDF::min( 16, $this->{KeyLength} + 5 ): 10 ),
			);
		}
		if( defined $this->{CallBack} ){
			&{$this->{CallBack}}( { ObjId => $node->{ObjId}, ObjNum => $this->{ObjectID}, CurrLen => $this->{CurrOffset} } );
		}
		$node->makeCode( );
		# If the file pointer stays, the object didn't produce any code.
		if( tell( $this->{FileHandle} ) == $this->{CurrOffset} ){
			$this->{XrefTable}->[ $node->{ObjId} ] = 0;
		}
		$this->{ObjectById}->[ $node->{ObjId} ] = $node;	# Watch here!
	} else {
		$node = $this;
	}
	my $p = $node->{son};
	if( $p ){
		while( $p ){
			$this->printTree( $p );
			$p = $p->{next};
		}
	}
	$node->cleanUp( );
}

sub excludePObject {
	my( $this, $pobj ) = @_;
	$this->{ExcludedPObjs}->{ $pobj } = 1;
}

# Write PDF output. $fname is a file name, $attr is a hash ref, both optional.
# $callback is a code ref that needs params: ObjNum (total obj ID), ObjId (current id), CurrLen (current length)
sub writePDF {
	my( $this, $fname, $attr, $callback ) = @_;
	my $oldroot = $PDF::root;
	&PDF::choose( $this );
	# Computer document encryption key
	if( ref( $attr ) eq 'HASH' &&
		scalar( grep { exists $attr->{$_} } qw(OwnerPwd UserPwd Print Select Change ChangeAll) ) ){
		$this->setSecurity( $attr );
	}
	if( $this->{Encrypt} ){
		$this->{Encrypt}->prepareFile( );
	}
	if( !defined $fname ){
		$fname = $this->{Prefs}->{FileName};
	}
	$fname =~ s/[\/\\]+/\//g;
	if( $ENV{REMOTE_ADDR} && $fname eq '' ){	# Backward-compatibility code; for use in CGI environment
		print "Content-type: application/pdf\n\n";
	}
	# The following line gets a temporary file name
	my $file = $PDF::TempDir . '/' . join( '', 'PEV', substr( unpack( 'H*', $this->{FileID} ), 0, 8 ), '.TMP' );
	$this->{FileHandle} = new FileHandle( );
	$this->{FileHandle}->open( "+>$file" ) or croak "Can't open temporary file $file";
	binmode( $this->{FileHandle} );
	my $oldout = select( $this->{FileHandle} );
	$this->{CurrOffset} = 0;
	$this->{ObjectID} = 0;
	$this->assignObjectIds( );
	$this->assignImportedObjectIds( );

	print "\%PDF-", $this->{Version}, "\x0D\x0A\%\xE2\xE3\xCF\xD3\x0D\x0A";
	if( defined $callback && ref( $callback ) eq 'CODE' ){
		$this->{CallBack} = $callback;
	}
	$this->printTree( );
	my $callval = { ObjId => 0, ObjNum => $this->{ObjectID}, CurrLen => 0 };
	for my $pobj ( @{$this->{ObjectById}} ){	# Now print imported objects
		next unless( defined $pobj && ref( $pobj ) eq 'PObject' );
		next if( defined $this->{ExcludedPObjs}->{ $pobj } );
		$this->{CurrOffset} = $this->{FileHandle}->tell( );
		if( defined $this->{CallBack} ){
			$callval->{ObjId} = $pobj->{ObjId};
			$callval->{CurrLen} = $this->{CurrOffset};
			&{$this->{CallBack}}( $callval );
		}
		if( $this->{Encrypt} ){
			$pobj->encryptIt( $this->{EKey}, $this->{StrongEnc} );
		}
		$pobj->printIt( );
		unless( ref( $attr ) eq 'HASH' && $attr->{Final} ){	# if Final is 1, the imported data are encrypted but not decrypted back.
			if( $this->{Encrypt} ){	# Now decrypt it!
				$pobj->encryptIt( $this->{EKey}, $this->{StrongEnc} );
			}
		}
		$this->{XrefTable}->[ $pobj->{ObjId} ] =
			sprintf( "%010d 00000 n\x0D\x0A", $this->{CurrOffset} );
	}
	$this->{CurrOffset} = $this->{FileHandle}->tell( );
	my $XrefTabLen = scalar @{$this->{XrefTable}};
	my $LastFreeEntry = 0;
	for( my $i = $XrefTabLen - 1; $i > 0; $i-- ){
		if( !$this->{XrefTable}->[$i] ){
			$this->{XrefTable}->[$i] = sprintf( "%010d 00001 f\x0D\x0A", $LastFreeEntry );	# Revision number is always 1
			$LastFreeEntry = $i;
		}
	}
	$this->{XrefTable}->[0] = sprintf( "%010d 65535 f\x0D\x0A", $LastFreeEntry );
	my $fileid = unpack( 'H*', $this->{FileID} );
	print join( $PDF::endln,
		'xref',
		qq{0 $XrefTabLen},
		join( '', @{$this->{XrefTable}}, 'trailer' ),
		'<<',
		qq{/Size $XrefTabLen},
		qq{/Info $this->{DocInfo}->{ObjId} 0 R},
		qq{/Root $this->{Catalog}->{ObjId} 0 R},
		'',
	);
	if( $this->{Encrypt} ){
		print qq{/Encrypt $this->{Encrypt}->{ObjId} 0 R }, $PDF::endln;
	}
	print join( $PDF::endln,
		qq{/ID[<$fileid><$fileid>]},
		'>>',
		'startxref',
		$this->{CurrOffset},
	);
	print qq{$PDF::endln\%\%EOF$PDF::endln};
	$this->{FileHandle}->close( );
	select( $oldout );
	if( $fname ne '' ){
		if( -e $fname ){
			unlink( $fname ) or croak "Can't overwrite output file $fname; temporary output is stored in $file";
		}
		move( $file, $fname ) or croak "Can't rename temporary file $file to $fname";
	} else {
		$this->{FileHandle}->open( "<$file" ) or croak "Can't open file $file.";
		binmode( $this->{FileHandle} );
		binmode( STDOUT );
		my $buffer;
		while( read( $this->{FileHandle}, $buffer, 4096 ) ){
			print $buffer;
		}
		$this->{FileHandle}->close( );
		unlink( $file ) or croak "Can't remove temporary file $file.";
	}
	$this->{DocInfo}->setFileID( );		# Reset file ID for next file.
	&PDF::choose( $oldroot ) if( $oldroot );
	%{$this->{ExcludedPObjs}} = ( );
	for( values %{$this->{LayerIds}} ){
		$_->{par}->deleteChild( $_ );
	}
	%{$this->{LayerIds}} = ( );
	@{$this->{XrefTable}} = ( );
}

sub getImportedFile {
	my( $this, $fname ) = @_;
	for my $filename ( keys %{$this->{ImportedFiles}} ){
		if( $filename eq $fname ){
			return PDF::getPDFFile( $filename );
		}
	}
	return new PDFFile( $fname );
}

# For backward-compatibility only
sub showTreeStruct {
	my $this = shift;
	my $ptr;
	if( !defined $this ){
		$this = $PDF::root;
	}
	print "\t" x $PDF::dep, $this, "\n";
	$ptr = $this->{son};
	$PDF::dep++;
	if( $ptr ){
		while( $ptr ){
			&showTreeStruct( $ptr );
			$ptr = $ptr->{next};
		}
	}
	$PDF::dep--;
}

# For internal use only.
sub traverseXML {
	my $this = shift;
	my $node = shift;
	my $class = ref( $node );
	$class =~ s/^(\w+::)+//;	# Remove class path names.
	if( exists $PDF::PDFeverModules{ $class } ){
		&{ $PDF::PDFeverModules{ $class } }( $node );
	}
	if( exists $node->{Kids} && @{$node->{Kids}} ){
		for( @{$node->{Kids}} ){
			$this->traverseXML( $_ );
		}
	}
}

# Require a XML file name or content; returns a new PDFDoc object
sub importXML {
	my $this = shift;	# It doesn't matter whether $this is defined or not.
	my $file = shift;
	my $parser = new XML::Parser( Style => 'Objects', ProtocolEncoding => 'ISO-8859-1' );
	# If $file is not defined, try the command line argument
	if( !defined $file ){
		$file = $main::ARGV[0];
	}
	# If $file is still not defined, try read from STDIN
	if( !defined $file ){
		$file = join( "\n", <> );
	}
	my $xml = ( $file =~ m/[<>]/? $parser->parse( $file )->[0]: $parser->parsefile( $file )->[0] );
	if( $xml->{Width} && $xml->{Height} ){
		$xml->{Box} = new Rect( 0, 0, $xml->{Width}, $xml->{Height} );
	}
	bless $xml, 'HASH';		# Treat it as a regular hash ref
	my $oldroot = $PDF::root;
	my $that = new PDFDoc( $xml );
	$that->traverseXML( $xml );
	PDF::choose( $oldroot ) if( $oldroot );
	return $that;
}

# Write the XML representation of the current PDF file.
sub exportXML {
	my( $this, $node ) = @_;
	my $oldroot;
	if( defined $node && !$node->isa( 'PDFTreeNode' ) ){
		croak "The function exportXML doesn't take any argument";
	}
	if( !defined $node ){
		$oldroot = $PDF::root;
		PDF::choose( $this );
		$node = $this;
		print '<?xml version="1.0" standalone="yes"?>', "\n<PDF";
		for( keys %{$this->{Prefs}} ){
			next if !length( $this->{Prefs}->{$_} );
			print qq{ $_="}, &PDF::escXMLChar( $this->{Prefs}->{$_} ), '"';
		}
		print '>', "\n";
		map { print "\t$_\n"; } @{$this->{AddXML}};
		$this->{dep} = 0;
	} else {
		$node->startXML( PDF::max( 0, $this->{dep} - 2 ) );
	}
	my $ptr = $node->{son};
	$this->{dep}++;
	if( $ptr ){
		while( $ptr ){
			$this->exportXML( $ptr );
			$ptr = $ptr->{next};
		}
	}
	$this->{dep}--;
	if( $node == $this ){
		print "</PDF>\n";
	} else {
		$node->endXML( PDF::max( 0, $this->{dep} - 2 ) );
	}
	PDF::choose( $oldroot ) if( defined $oldroot );
}

# Add one or more content objects to the page template; order is preserved.
sub addToTemplate {
	my $this = shift;
	for my $obj ( @_ ){
		next if( !ref($obj) || $obj->{IsTemplate} || !exists $PDFDoc::TemplateModules{ ref($obj) } );
		$this->{Template}->[0]->{$obj} = scalar @{$this->{Template}};
		$obj->{IsTemplate} = 1;
		push( @{$this->{Template}}, $obj );
	}
}

sub getTemplate {
	my $this = shift;
	my @objs = @{$this->{Template}};
	shift( @objs );
	return @objs;
}

sub dropFromTemplate {
	my $this = shift;
	my @idxs = ( );
	for my $obj ( @_ ){
		next if( !ref($obj) || !defined $this->{Template}->[0]->{$obj} );
		push( @idxs, $this->{Template}->[0]->{$obj} );
	}
	return unless( @idxs );
	@{$this->{Template}}[ @idxs ] = ( );
	my @objs = splice( @{$this->{Template}}, 1 );
	$this->{Template}->[0] = {};
	for( @objs ){ $_->{IsTemplate} = 0; }
	$this->addToTemplate( @objs );
}

sub resetTemplate {
	my $this = shift;
	map { $_->{IsTemplate} = 0; } splice( @{$this->{Template}}, 1 );
	$this->{Template}->[0] = {};
}

sub setFontEncoding {
	my( $this, $encoding ) = @_;
	my %schemes = map { $_, 1 } qw(WinAnsiEncoding PDFDocEncoding MacRomanEncoding StandardEncoding);
	if( defined $schemes{$encoding} ){
		$this->{Prefs}->{FontEncoding} = $encoding;
	}
}

# Load a predefined **Type1** font into the current document
# In this version it only uses built-in Type1 fonts
sub loadFont {
	my( $this, $FontName, $Encoding ) = @_;
	# Solving the problem of multiple names for a single font.
	$FontName = PDFFont::getFontTrueName( $FontName );
	# If the font has been loaded or the font name is not one of the predefined, skip.
	# Note: $this->{Fonts}->{$FontName}->{$Encoding} may have been defined by setFontVariant!!!
	if( defined $this->{Fonts}->{$FontName}->{$Encoding} && defined $this->{Fonts}->{$FontName}->{$Encoding}->{BaseFont}
		|| !exists $PDFFont::Fonts{$FontName} ){
		return;
	}
	$this->{Fonts}->{$FontName}->{$Encoding} ||= { };	# May have been defined by setFontVariant but not loaded!!!
	for( keys %{$PDFFont::Fonts{$FontName}} ){
		next if( exists $this->{Fonts}->{$FontName}->{$Encoding}->{$_} );
		$this->{Fonts}->{$FontName}->{$Encoding}->{$_} = $PDFFont::Fonts{$FontName}->{$_};
	}
	# We have to duplicate a width array because the elements vary with encoding.
	$this->{Fonts}->{$FontName}->{$Encoding}->{Widths} = [ ];
	@{$this->{Fonts}->{$FontName}->{$Encoding}->{Widths}} = @{$PDFFont::Fonts{$FontName}->{Widths}};
}

# Get the PDFFont object for a given font name. If the font has not been
# installed, install it first. If the font doesn't have a corresponding
# PDFFont object, create it before returning anything. If the requested
# font is recognized, return the PDFFont for Times-Roman.
sub getFont {
	my( $this, $FontName, $Encoding ) = @_;
	$FontName = PDFFont::getFontTrueName( $FontName );
	$Encoding ||= $this->{Prefs}->{FontEncoding} || 'WinAnsiEncoding';
	if( !exists $this->{Fonts}->{$FontName} || !exists $this->{Fonts}->{$FontName}->{$Encoding} 
		|| !exists $this->{Fonts}->{$FontName}->{$Encoding}->{BaseFont} ){	# Font not installed
		if( !exists $PDFFont::Fonts{$FontName} ){	# Font not recognized
			$FontName = 'Times-Roman';
		}
		$this->loadFont( $FontName, $Encoding );
		$this->buildType1FontWidth( $FontName, $Encoding );
	}
	if( !exists $this->{Fonts}->{$FontName}->{$Encoding}->{FontObj} ){
		my $oFont = defined $Encoding? new PDFFont( $FontName, $Encoding ): new PDFFont( $FontName );
		$this->{Fonts}->{$FontName}->{$Encoding}->{FontObj} = $oFont->getName( );
	}
	return $this->getObjByName( $this->{Fonts}->{$FontName}->{$Encoding}->{FontObj} );
}

# Build type 1 font width (font can be built-in or embedded)
sub buildType1FontWidth {
	my( $this, $FontName, $Encoding ) = @_;
	$FontName = PDFFont::getFontTrueName( $FontName );
	# If the font has not been loaded, return
	if( !exists $this->{Fonts}->{$FontName}->{$Encoding} ){
		return;
	}
	my $FontPtr = $this->{Fonts}->{$FontName}->{$Encoding};
	# Deals with only Type1 fonts
	if( $FontPtr->{Subtype} ne 'Type1' ){
		return;
	}
	# Embedded Type1 fonts using StandardEncoding are skipped.
	if( exists $FontPtr->{Encoding} && $FontPtr->{Encoding} eq 'StandardEncoding' ){
		return;
	}
	# Symbol and ZapfDingbats use special encoding scheme therefore are skipped.
	return if( $FontPtr->{BaseFont} eq 'Symbol' || $FontPtr->{BaseFont} eq 'ZapfDingbats' );
	$FontPtr->{Encoding} = ( $Encoding || $this->{Prefs}->{FontEncoding} || 'WinAnsiEncoding' );
	if( $FontPtr->{BaseFont} eq 'Courier' ){
		$FontPtr->{FirstChar} = ( $Encoding eq 'PDFDocEncoding'? 24: 32 );
		return;
	}
	my $ByCode = $FontPtr->{Widths};
	my $ByName = $FontPtr->{AvailWidths};
	my %schemes = map { $_, 1 } qw(WinAnsiEncoding PDFDocEncoding MacRomanEncoding StandardEncoding);
	if( !exists $schemes{$Encoding} ){
		$Encoding = 'StandardEncoding';
	}
	my $EncodingArray = {
		WinAnsiEncoding => \@PDFFont::WinAnsiEncoding,
		PDFDocEncoding  => \@PDFFont::PDFDocEncoding,
		MacRomanEncoding => \@PDFFont::MacRomanEncoding,
		StandardEncoding => \@PDFFont::StandardEncoding,
	}->{$Encoding};
	map{ $ByCode->[ $_ + 95 ] = ( $ByName->{ $EncodingArray->[$_] } || 1000 ); } 0..( scalar( @$EncodingArray ) - 1 );
	if( $Encoding eq 'PDFDocEncoding' ){
		unshift( @{$ByCode},
			( map{ $ByName->{ $PDFFont::PDFDocEncodingExtra[$_] } } 0..7 )
		);
		$FontPtr->{FirstChar} = 24;
	} else {
		$FontPtr->{FirstChar} = 32;
	}
}

sub usePFB {
	my( $this, $PFBFile, $FMFile, $embed, $FontName ) = @_;	# $FMFile can be the name of a AFM of PFM file
	if( !defined $FMFile || $FMFile !~ /\.AFM$/i && $FMFile !~ /\.PFM$/i ){
		croak "Please specify an AFM/PFM file name in usePFB.";
	}
	my $BaseFont;	# Font name
	my $FM = new FileHandle;
	$FMFile = &PDF::secureFileName( $FMFile );
	if( !open( $FM, "<$FMFile" ) ){
		croak "Can't open file $FMFile in usePFB.";
	}
	my $ThisFont = { };
	my $FontWidth = [ ];
	my $FontWidthHash = { };
	if( $FMFile =~ /\.AFM$/i ){
		my( %FontDef, %FontNData, @FontCData, $line );
		while( $line = <$FM> ){
			chomp $line;
			last if( $line =~ /^C\s+[0-9\-]+\s*;\s*WX\s+[0-9\-]+/ );
			my @defs = split( /\s+/, $line, 2 );
			$FontDef{ $defs[0] } = $defs[1];
		}
		push( @$FontWidth, (0) x 224 );		# Initiate 224 zeros because chars are not filling the spaces in continuity
		if( defined $FontName ){
			$BaseFont = $FontName;
		} else {
			$BaseFont = $FontDef{FontName};	# PostScript font data
		}
		$BaseFont =~ s/\x00//g;	# Remove zeros in names
		$BaseFont = PDF::strToName( $BaseFont );
		if( exists $this->{Fonts}->{$BaseFont}->{StandardEncoding} || exists $PDFFont::Fonts{$BaseFont} ){
			close( $FM );
			croak "Font name $BaseFont has already been used for another font.";
		}
		$ThisFont->{BaseFont} = $BaseFont;
		my $DesPtr = $ThisFont->{FontDescriptor} = { };
		for( qw(StemV StemH CapHeight XHeight) ){
			next unless exists $FontDef{$_};
			$DesPtr->{$_} = $FontDef{$_};
		}
		$DesPtr->{Descent} = $FontDef{Descender};
		$DesPtr->{Ascent} = $FontDef{Ascender};
		$ThisFont->{Widths} = $FontWidth;
		$ThisFont->{AvailWidths} = $FontWidthHash;
		my @bbox = split( /\s+/, $FontDef{FontBBox} );
		$DesPtr->{FontBBox} = [ @bbox[0..3] ];
		$ThisFont->{FirstChar} = 32;
		$ThisFont->{LastChar} = 255;
		$ThisFont->{Subtype} = 'Type1';
		$ThisFont->{FontObj} = 0;
		$DesPtr->{FontFile} = $PFBFile;
		$DesPtr->{ItalicAngle} = $FontDef{ItalicAngle};
		$DesPtr->{StemV} = $FontDef{StdVW} || 0;
		$DesPtr->{StemH} = $FontDef{StdHW} || 0;
		$DesPtr->{Flags} = 0x0020;
		$DesPtr->{Flags} |= 0x0001 if( $FontDef{IsFixedPitch} eq 'true' );
		$DesPtr->{Flags} |= 0x0040 if( $FontDef{ItalicAngle} != 0 );
		while( $line =~ /^C\s+[0-9\-]+\s*;\s*WX\s+[0-9\-]+/ ){
			my @segs = split( /\s*;\s*/, $line );
			next if( @segs < 2 );
			my %ThisChar = ( );
			foreach( @segs ){
				my( $ent, $val ) = split( /\s+/, $_, 2 );
				$ThisChar{$ent} = $val;
			}
			if( $ThisChar{C} < 0 ){
				$ThisChar{C} = 32;
			}
			if( $ThisChar{C} < 32 || $ThisChar{C} > 127 ){
				$FontWidthHash->{ $ThisChar{N} } = $ThisChar{WX};
			} else {
				$FontWidth->[ $ThisChar{C} - 32 ] = $ThisChar{WX};
			}
			$line = <$FM>;
		};
	} elsif( $FMFile =~ /\.PFM$/i ){
		binmode( $FM );
		local $/;
		undef $/;
		my $Data = <$FM>;
		my @BData = unpack( 'vVa60v7C3vCvvCvvC4vV4vV7v26', $Data );
		my $flag = 0x0020;		# Non-symbolic
		$flag |= 0x0001 if( $BData[17] % 2 == 0 );	# PitchFamily. If odd, char is proportional, otherwise fixed.
		$flag |= 0x0008 if( $BData[17] & 48 );		# Script-like
		$flag |= 0x0002 if( $BData[17] & 16 );		# Serif-like
		$flag |= 0x0040 if( $BData[10] != 0 );		# Italic angle non-zero
		my @info = split( /\x00/, substr( $Data, 0xC7, $BData[31] - 0xC7 ) );	# 'PostScript', Windows name, PS name
		if( defined $FontName ){
			$BaseFont = $FontName;
		} else {
			$BaseFont = $info[2];
		}
		$BaseFont =~ s/\x00//g;	# Remove zeros in names
		$BaseFont = PDF::strToName( $BaseFont );
		if( exists $this->{Fonts}->{$BaseFont}->{StandardEncoding} || exists $PDFFont::Fonts{$BaseFont} ){
			close( $FM );
			croak "Font name $BaseFont has already been used for another font.";
		}
		$ThisFont = {
			'Subtype' => 'Type1',
			'BaseFont' => $BaseFont,
			'FirstChar' => $BData[20],
			'LastChar' => ( $BData[21] || 255 ),
			'Widths' => $FontWidth,
			'AvailWidths' => $FontWidthHash,
		};
		$ThisFont->{FontDescriptor} = {
			'Ascent' => $BData[7],
			'CapHeight' => $BData[44],
			'Descent' => $BData[47] * (-1),
			'Flags' => $flag,
			'ItalicAngle' => $BData[10],
			'AvgWidth' => $BData[18],
			'MaxWidth' => $BData[19],
			'FontFile' => $PFBFile,
			'FontBBox' => [ ],
		};
		# The Widths array contain data for all chars, which are Standard encoded.
		# This is forced by checking the Encoding field of this hash when calling buildType1FontWidth.
		push( @$FontWidth, unpack( 'v224', substr( $Data, $BData[31], ( $BData[21] - $BData[20] + 1 ) * 2 ) ) );
		push( @$FontWidth, ( 0 ) x ( 224 - scalar @$FontWidth ) );
		if( $BData[20] < 32 ){
			$ThisFont->{FirstChar} = 32;
			splice( @$FontWidth, 32 - $BData[20] );
		}
		if( $BData[21] < 255 ){		# Discard unnecessary elements
			splice( @$FontWidth, $BData[21] - 255 );
		}
	}
	close( $FM );
	$ThisFont->{Encoding} = 'StandardEncoding';
	unless( @{$ThisFont->{FontDescriptor}->{FontBBox}} ){
		my $PFB = new FileHandle;
		$PFBFile = &PDF::secureFileName( $PFBFile );
		if( !open( $PFB, "<$PFBFile" ) ){
			croak "Can't open file $PFBFile in usePFB.";
		}
		while( <$PFB> ){
			next unless( m|/FontBBox\s*\{\s*([0-9\- ]+)\}| );
			my @bbox = split( /\s+/, $1 );
			push( @{$ThisFont->{FontDescriptor}->{FontBBox}}, @bbox[0..3] );
			last;
		}
		close( $PFB );
	}
	$this->{Fonts}->{$BaseFont}->{StandardEncoding} = $ThisFont;
	for( qw(Normal Bold Italic BoldItalic) ){
		$ThisFont->{$_} = $BaseFont;
	}
	if( $embed ){
		$ThisFont->{Embed} = 1;
	}
	$this->addXML( join '', qq{<Font Name="$BaseFont" Embed="$embed" PFB="}, &PDF::escXMLChar( $PFBFile ), '" FM="', &PDF::escXMLChar( $FMFile ), '"/>' );
	return $BaseFont;
}

sub useTTF {
	my( $this, $FontFile, $embed, $FontName ) = @_;
	$FontFile = &PDF::secureFileName( $FontFile );
	my $TTF = new FileHandle;
	if( open( $TTF, "<$FontFile" ) ){
		binmode $TTF;
	} else {
		croak "Can't open font file $FontFile in useTTF";
	}
	my( $chunk, $tbl, $BaseFont );

	# Step 1: Read the file header, then read in the desired tables into a hash

	read( $TTF, $chunk, 12 );
	my ( $dummy, $numTables ) = unpack( 'Nn*', $chunk );
	my %tables = ( );
	for( 1..$numTables ){
		read( $TTF, $chunk, 16 );
		my @entry = unpack( 'A4NNN', $chunk );	# Tag, checkSum, offset, length
		$tables{ $entry[0] } = [ $entry[2], $entry[3] ];
	}

	my %patterns = (
		'OS/2' => 'n16C10b128A4n*',
		'cmap' => 'nn',
		'head' => 'N4b16nc16n*',
		'hhea' => 'Nn*',
		'maxp' => 'Nn*',
		'name' => 'n3',
		'post' => 'n6N*',
	);

	foreach $tbl ( keys %patterns ) {
		seek( $TTF, $tables{$tbl}->[0], 0 );
		read( $TTF, $chunk, $tables{$tbl}->[1] );
		$tables{$tbl}->[2] = [ unpack( $patterns{$tbl}, $chunk ) ];
	}

	my $emratio = 1000 / $tables{head}->[2]->[5];
	# Step 2: Find the PostScript name of the font

	if( defined $FontName ){
		$BaseFont = $FontName;
	} else {
		seek( $TTF, $tables{name}->[0]+6, 0 );
		for( 1..$tables{name}->[2]->[1] ){
			read( $TTF, $chunk, 12 );
			my @rec = unpack( 'n*', $chunk );
			next unless( $rec[3] == 6 );
			read( $TTF, $chunk, ( $tables{name}->[2]->[1] - $_ ) * 12 );
			read( $TTF, $chunk, $tables{name}->[1] - $tables{name}->[2]->[2] );
			$BaseFont = substr( $chunk, $rec[5], $rec[4] );
			last;
		}
	}
	$BaseFont =~ s/\x00//g;	# Remove zeros in names
	if( length $BaseFont == 0 ){
		croak "Can't understand this font file";
	}
	$BaseFont = PDF::strToName( $BaseFont );
	if( exists $this->{Fonts}->{$BaseFont}->{WinAnsiEncoding} || exists $PDFFont::Fonts{$BaseFont} ){
		close( $TTF );
		croak "Font name $BaseFont has already been used for another font";
	}
	for( qw(head hhea cmap hmtx) ){
		if( !exists $tables{$_} ){
			croak "Expected header $_ in font file $FontFile";
		}
	}

	my $ThisFont = $this->{Fonts}->{$BaseFont}->{WinAnsiEncoding} = {
		'Subtype' => 'TrueType',
		'BaseFont' => $BaseFont,
		'FontDescriptor' => {
			'FontBBox' => [
				int( ( $tables{head}->[2]->[22] - ( $tables{head}->[2]->[22] > 32767? 65536: 0 ) ) * $emratio ),
				int( ( $tables{head}->[2]->[23] - ( $tables{head}->[2]->[23] > 32767? 65536: 0 ) ) * $emratio ),
				int( $tables{head}->[2]->[24] * $emratio ),
				int( $tables{head}->[2]->[25] * $emratio ),
			],
			'CapHeight' => int( $tables{hhea}->[2]->[1] * $emratio ),
			'Ascent' => int( $tables{hhea}->[2]->[1] * $emratio ),
			'Descent' => int( ( $tables{hhea}->[2]->[2] - ( $tables{hhea}->[2]->[2] > 32767? 65536: 0 ) ) * $emratio ),
			'StemV' => 0,
			'MaxWidth' => int( $tables{hhea}->[2]->[4] * $emratio ),
			'FontFile' => $FontFile
		},
	};

	# Step 3: Read char width data

	my $segCount = 0;
	seek( $TTF, $tables{cmap}->[0]+4, 0 );
	for( 1..$tables{cmap}->[2]->[1] ){
		read( $TTF, $chunk, 8 );
		my @rec = unpack( 'nnN', $chunk );
		next unless( $rec[0] == 3 && $rec[1] == 1 );
		seek( $TTF, $tables{cmap}->[0]+$rec[2], 0 );
		read( $TTF, $chunk, 14 );
		@rec = unpack( 'n*', $chunk );
		$segCount = $rec[3];
		last;
	}
	read( $TTF, $chunk, $segCount + 2 );
	my @endCount = unpack( 'n*', $chunk );
	read( $TTF, $chunk, $segCount );
	my @startCount = unpack( 'n*', $chunk );
	read( $TTF, $chunk, $segCount );
	my @idDelta = unpack( 'n*', $chunk );
	read( $TTF, $chunk, $segCount );
	my @idRangeOffset = unpack( 'n*', $chunk );
	read( $TTF, $chunk, $tables{cmap}->[1] - $segCount * 4 - 16 );
	my @glyphIDArray = unpack( 'n*', $chunk );
	$ThisFont->{FirstChar} = ( $startCount[0] || 32 );
	my @chars = ( 0 ) x 256;
	my( $s, $c );
	for $s ( 0..$segCount/2-1 ){
		$endCount[$s] > 255 && ( $endCount[$s] = 255 );
		last if( $startCount[$s] == 65535 );
		$idDelta[$s] > 32767 && ( $idDelta[$s] -= 65536 );
		for $c ( $startCount[$s]..$endCount[$s] ){
			if( !defined $c ){
				$c = 32;
			}
			$chars[$c - 32] = $c + $idDelta[$s];
			if( $idRangeOffset[$s] ){
				$chars[$c - 32] = $glyphIDArray[ $idRangeOffset[$s] / 2 + $c - $startCount[$s] + $s - $segCount/2 ];
			}
			last if( $c == 255 );
		}
	}
	$ThisFont->{LastChar} = 255;
	my $FontWidth = [ ];
	seek( $TTF, $tables{hmtx}->[0], 0 );
	for( 1..$tables{hhea}->[2]->[-1] ){
		read( $TTF, $chunk, 4 );
		my( $wid, $lsb ) = unpack( 'n2', $chunk );
		$lsb > 32767 && ( $lsb -= 65536 );
		if( $emratio != 1 ){
			$wid *= $emratio;
			$lsb *= $emratio;
		}
		push( @$FontWidth, int( $wid ) );
	}
	$ThisFont->{FontDescriptor}->{MissingWidth} = $FontWidth->[0];
	@$FontWidth = @$FontWidth[@chars];
	$ThisFont->{Widths} = $FontWidth;
	close( $TTF );

	# Step 4: additional information from optional tables

	if( exists $tables{'OS/2'} ){
		$ThisFont->{FontDescriptor}->{AvgWidth} = int( $tables{'OS/2'}->[2]->[1] * $emratio );
		my $flag = 0;
		my @panose = @{$tables{'OS/2'}->[2]}[16..25];
		$flag |= 0x0001 if( $panose[3] == 9 );
		$flag |= 0x0002 if( $panose[1] < 11 || $panose[1] > 13 );
		$flag |= 0x0004 if( $panose[0] != 2 );
		$flag |= 0x0008 if( $panose[0] == 3 );
		$flag |= 0x0020 if( $panose[0] == 2 );
		$flag |= 0x0040 if( $panose[7] >= 9 );
		$ThisFont->{FontDescriptor}->{Flags} = $flag;
	} else {
		$ThisFont->{FontDescriptor}->{AvgWidth} = $ThisFont->{FontDescriptor}->{MaxWidth};
		$ThisFont->{FontDescriptor}->{Flags} = 32;
	}

	if( exists $tables{post} ){
		$ThisFont->{FontDescriptor}->{ItalicAngle} = int( $tables{post}->[2]->[2] - ( $tables{post}->[2]->[2] > 32767? 65536: 0 ) );
	}

	# Last step: register to the main program

	for( qw(Normal Bold Italic BoldItalic) ){
		$ThisFont->{$_} = $BaseFont;
	}

	if( $embed ){
		$ThisFont->{Embed} = 1;
	}
	$this->addXML( join '', qq{<Font Name="$BaseFont" Embed="$embed" TTF="}, &PDF::escXMLChar( $FontFile ), '"/>' );
	return $BaseFont;
}

# $rel must be 'Normal', 'Bold', 'Italic', or 'BoldItalic'
# $tofont and $fromfont must be font names
sub setFontVariant {
	my( $this, $fromfont, $rel, $tofont, $encoding ) = @_;
	$encoding ||= $this->{Prefs}->{Encoding} || 'WinAnsiEncoding';
	$this->{Fonts}->{$fromfont}->{$encoding}->{$rel} = $tofont;
	$this->addXML( qq{<FontVariant FromFont="$fromfont" ToFont="$tofont" Rel="$rel" Encoding="$encoding"/>} );
}

sub setFontAllVariants {
	my( $this, $rels, $encoding ) = @_;
	return if( !defined( $rels ) || ref( $rels ) ne 'HASH' );
	$encoding ||= $this->{Prefs}->{Encoding} || 'WinAnsiEncoding';
	for my $font ( values %$rels ){
		for my $rel ( keys %$rels ){
			$this->{Fonts}->{$font}->{$encoding}->{$rel} = $rels->{$rel};
		}
	}
	$this->addXML( qq{<FontVariants Normal="$rels->{Normal}" Bold="$rels->{Bold}" Italic="$rels->{Italic}" BoldItalic="$rels->{BoldItalic}" Encoding="$encoding"/>} );
}

sub setColorSpace {
	my( $this, $space ) = @_;
	my %spaces = map { $_ => 1 } qw(RGB Gray CMYK);
	if( exists $spaces{$space} ){
		$this->{Prefs}->{ColorSpace} = $space;
	}
}

# Register a new named color. An XML tag will be created.
# Arguments: color name, color components, color space
sub registerColor {
	my $this = shift;
	my $name = uc( shift );
	my( $color, $space ) = @_;
	if( $space ne 'RGB' && $space ne 'CMYK' && $space ne 'Gray' ){
		croak "Color space must be RGB, CMYK, or Gray.";
	}
	if( exists $Color::NamedColors{$name} || exists $PDF::root->{CustomColors}->{$name} ){
		croak "Color name $name already defined.";
	}
	my @comp = Color::tellColor( $color, $space );
	$PDF::root->addXML( qq{<Color Name="$name" Color="$color" Space="$space"/>} );
	$color = $PDF::root->{CustomColors}->{$name} = {
		'ColorSpace' => $space,
		'RGB' => [ 0, 0, 0 ],
		'CMYK' => [ 0, 0, 0, 1 ],
		'Gray' => [ 0 ],
	};
	if( $space eq 'RGB' ){
		for( 0..2 ){
			next if( !$comp[$_] );
			$color->{RGB}->[$_] = $comp[$_];
		}
		@{$color->{CMYK}} = &Color::rgbToCmyk( @{$color->{RGB}} );
		@{$color->{Gray}} = &Color::rgbToGray( @{$color->{RGB}} );
	} elsif( $space eq 'CMYK' ){
		for( 0..3 ){
			next if( !$comp[$_] );
			$color->{CMYK}->[$_] = $comp[$_];
		}
		@{$color->{RGB}} = &Color::cmykToRgb( @{$color->{CMYK}} );
		@{$color->{Gray}} = &Color::cmykToGray( @{$color->{CMYK}} );
	} elsif( $space eq 'Gray' ){
		if( $comp[0] ){
			$color->{RGB}->[0] = $comp[0];
		}
		@{$color->{CMYK}} = &Color::grayToCmyk( @{$color->{Gray}} );
		@{$color->{RGB}} = &Color::grayToRgb( @{$color->{Gray}} );
	}
}

# Document information functions

sub setTitle {
	my $this = shift;
	$this->getDocInfo( )->setTitle( shift );
}

sub setKeywords {
	my $this = shift;
	$this->getDocInfo( )->setKeywords( @_ );
}

sub setAuthor {
	my $this = shift;
	$this->getDocInfo( )->setAuthor( shift );
}

sub setSubject {
	my $this = shift;
	$this->getDocInfo( )->setSubject( shift );
}

sub setProducer {
	my $this = shift;
	$this->getDocInfo( )->setProducer( shift );
}

sub getTitle {
	return shift->getDocInfo( )->{Title};
}

sub getSubject {
	return shift->getDocInfo( )->{Subject};
}

sub getAuthor {
	return shift->getDocInfo( )->{Author};
}

sub swapPage {
	my $this = shift;
	$this->getPagesRoot( )->swapPage( @_ );
}

sub detachPDFFile {
	my( $this, $that ) = @_;
	if( exists $this->{ImportedFiles}->{$that->{FileName}} ){
		for my $pobj ( values %{$this->{ImportedFiles}->{$that->{FileName}}} ){
			$pobj->finalize( );
		}
		%{$this->{ImportedFiles}->{$that->{FileName}}} = ( );
		delete $this->{ImportedFiles}->{$that->{FileName}};
	}
}

# Table-related functions

sub setCurrTable {
	my( $this, $table ) = @_;
	push( @{$this->{Tables}}, $table );
}

sub undefCurrTable {
	my $this = shift;
	pop( @{$this->{Tables}} ) if( @{$this->{Tables}} );
}

sub resetAllTables {
	my $this = shift;
	@{$this->{Tables}} = ( );
}

sub getCell {
	my $this = shift;
	croak "Table undefined" unless( @{$this->{Tables}} );
	return $this->{Tables}->[-1]->getCell( @_ );
}

# Close temp file and try to release some references to help garbage collection.
sub finalize {
	my $this = shift;
	return if $this->{Finalized};
	my $idx = shift @{$this->{Template}};
	%$idx = ( );
	@{$this->{Template}} = ( );
	$idx = shift @{$this->{NameLookupTable}};
	%$idx = ( );
	@{$this->{NameLookupTable}} = ( );
	for( %{$this->{TplResources}} ){
		%{$this->{TplResources}->{$_}} = ( );
	}
	%{$this->{TplResources}} = ( );
	my $pages = $this->getPagesRoot( );
	for( @{$pages->{Kids}} ){
		if( ref( $_ ) eq 'PObject' ){
			$_->{Data}->{Parent} = 0;
		}
	}
	@{$this->{ObjectById}} = ( );
	for my $filename ( keys %{$this->{ImportedFiles}} ){
		for my $pobj ( values %{$this->{ImportedFiles}->{$_}} ){
			$pobj->finalize( );
		}
		%{$this->{ImportedFiles}->{$filename}} = ( );
	}
	%{$this->{ImportedFiles}} = ( );
	%{$this->{Fonts}} = ( );
	for( qw(DocInfo Catalog CurrPage Encrypt) ){
		delete $this->{$_};
	}
	undef $this->{FileHandle};
	$this->{Finalized} = 1;
}

sub destroy {
	PDFTreeNode::releaseNode( shift );
}

sub DESTROY {
	shift->destroy( );
}

sub newAnnot { PDF::choose( shift ); return new Annot( @_ ); }
sub newBookmark { PDF::choose( shift ); return new Outlines( @_ ); }
sub newField { PDF::choose( shift ); return new Field( @_ ); }
sub newForm { PDF::choose( shift ); return new AcroForm( @_ ); }
sub newGraph { PDF::choose( shift ); return new GraphContent( @_ ); }
sub newImage { PDF::choose( shift ); return new ImageContent( @_ ); }
sub newOutlines { PDF::choose( shift ); return new Outlines( @_ ); }
sub newPage { PDF::choose( shift ); return new Page( @_ ); }
sub newPreformText { PDF::choose( shift ); return new PreformText( @_ ); }
sub newShading { PDF::choose( shift ); return new PDFShading( @_ ); }
sub newTextBox { PDF::choose( shift ); return new FloatingText( @_ ); }
sub newTexture { PDF::choose( shift ); return new PDFTexture( @_ ); }
sub newXObject { PDF::choose( shift ); return new XObject( @_ ); }

sub setPageMode { my $this = shift; $this->getCatalog->setPageMode( @_ ); }
sub setPageLayout { my $this = shift; $this->getCatalog->setPageLayout( @_ ); }
sub setViewerPref { my $this = shift; $this->getCatalog->setViewerPref( @_ ); }

1;
