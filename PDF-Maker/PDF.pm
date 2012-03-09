#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package PDF;

$PDF::VERSION = 3.0;
$PDF::ApplicationName = 'PDFeverywhere 3.0';

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(choose root);
@EXPORT = qw(init startPDF startPDFDoc writePDF writePDFDoc importXML reformatText tellColor tellSize);

use bytes;
use strict;
use Carp;
use Carp::Heavy;
use XML::Parser;
use Compress::Zlib;

$PDF::root = 0;	# Current PDFDoc object

sub choose {
	my $doc = shift;
	if( ref( $doc ) ne 'PDFDoc' ){
		croak 'Must choose a PDFDoc object.';
	}
	$PDF::root = $doc;
}

use PDFUtil;
use PDFTreeNode;
use Shape;
use PDFFont;
use PDFDoc;
use Page;
use PDFFile;
use PDFStream;
use Annot;
use Appearance;
use GraphContent;
use ImageContent;
use XObject;
use PDFShading;
use PDFTexture;
use Field;
use AcroForm;
use TextContent;
use FloatingText;
use PreformText;

#===========================================================================#
# XML-related
#===========================================================================#

%PDF::PDFeverModules = (
	Font => sub {
		my $xml = shift;
		defined $xml->{TTF} && $PDF::root->useTTF( $xml->{TTF}, $xml->{Embed}, $xml->{Name} ) ||
		defined $xml->{PFB} && defined $xml->{FM} && $PDF::root->usePFB( $xml->{PFB}, $xml->{FM}, $xml->{Embed}, $xml->{Name} );
	},
	FontVariant => sub {
		my $xml = shift;
		$PDF::root->setFontVariant( $xml->{FromFont}, $xml->{Rel}, $xml->{ToFont}, $xml->{Encoding} );
	},
	FontVariants => sub {
		my $xml = shift;
		$PDF::root->setFontAllVariants( { Normal => $xml->{Normal}, Bold => $xml->{Bold}, Italic => $xml->{Italic}, BoldItalic => $xml->{BoldItalic} }, $xml->{Encoding} );
	},
	Form => sub{ AcroForm->newFromXML( shift ); },
	Annot => sub { Annot->newFromXML( shift ); },
	Field => sub { Field->newFromXML( shift ); },
	Text => sub {
		my $xml = shift;
		$xml->{Preform}?
			PreformText->newFromXML( $xml ):
			FloatingText->newFromXML( $xml );
	},
	DrawGrid => sub {
		my $xml = shift;
		bless $xml, 'HASH';
		for my $at ( 'Widths', 'Heights' ){
			next unless( defined $xml->{$at} );
			my @arr = split( /,\s*/, $xml->{$at} );
			$xml->{$at} = [ @arr ];
		}
		my $host = $PDF::root->getCurrPage( )->getArtBox( );
		my $rect = defined $xml->{Rect}? new Rect( split( /,\s*/, $xml->{Rect} ) ): $host->anchorRect(
			( exists $xml->{Width}? $xml->{Width}: undef ),
			( exists $xml->{Height}? $xml->{Height}: undef ),
			( exists $xml->{Anchor}? $xml->{Anchor}: undef ),
			new Rect( $host ) );
		$PDF::root->getCurrPage( )->drawTable( $rect->{Left}, $rect->{Bottom}, $rect->{Width}, $rect->{Height}, ( $xml->{Fill} || 0 ), $xml );
		if( defined $xml->{Kids} && @{$xml->{Kids}} ){
			for my $kid ( @{$xml->{Kids}} ){
				next if( ref( $kid ) =~ /::Characters$/ );
				$kid->{RowSpan} ||= 1;
				$kid->{ColSpan} ||= 1;
				$rect = $PDF::root->getCell( $kid->{Row}, $kid->{Col}, $kid->{RowSpan}, $kid->{ColSpan} );
				$rect = $rect->anchorRect(
					( exists $kid->{Width}? $kid->{Width}: undef ),
					( exists $kid->{Height}? $kid->{Height}: undef ),
					( exists $kid->{Anchor}? $kid->{Anchor}: undef ),
					new Rect( $rect ),
				);
				$kid->{Rect} = join( ', ', $rect->{Left}, $rect->{Bottom}, $rect->{Right}, $rect->{Top} );
				$PDF::root->traverseXML( $kid );
			}
		}
		$PDF::root->undefCurrTable( );
	},
	Graph => sub { GraphContent->newFromXML( shift ); },
	Image => sub { ImageContent->newFromXML( shift ); },
	Import => sub {
		my $xml = shift;
		$PDF::root->importPages( $PDF::root->getImportedFile( $xml->{File} ), split( /,\s+/, $xml->{Pages} ) );
	},
	Outlines => sub { Outlines->newFromXML( shift ); },
	Page => sub { Page->newFromXML( shift ); },
	Shading => sub { PDFShading->newFromXML( shift ); },
	Texture => sub { PDFTexture->newFromXML( shift ); },
	XObject => sub { XObject->newFromXML( shift ); },
);

#===========================================================================#
# Backward-compatibility functions
#===========================================================================#

sub getObjByName {
	my $name = shift;
	return $PDF::root->getObjByName( $name );
}

sub addToTemplate {
	$PDF::root->addToTemplate( @_ ) if( $PDF::root );
}

sub dropFromTemplate {
	$PDF::root->dropFromTemplate( @_ ) if( $PDF::root );
}

sub resetTemplate {
	$PDF::root->resetTemplate( @_ ) if( $PDF::root );
}

sub init {	# Its use strongly discouraged.
	my $NoInput = shift;
	*main::PageSizes = *Pages::PageSizes;
	*main::SizeToPoint = *PDF::SizeToPoint;
	*main::NamedColors = *Color::NamedColors;
	*main::root = *PDF::root;
	if( defined %main::Defaults ){
		map{ unless( defined $main::fields{$_} ){
			$main::fields{$_} = $main::Defaults{$_};
		}  } keys %main::Defaults;
	}
	new PDFDoc( );
	return if( defined $NoInput && $NoInput );
	if( defined $ARGV[0] ){
		my $fh = new FileHandle( );
		$fh->open( "<$ARGV[0]" );
		if( defined $fh ){
			$main::fields{Text} = $fh->getlines;
		}
		$fh->close( );
	} else {
		$main::fields{Text} = '';
		while( <> ){
			$main::fields{Text} .= $_;
		}
	}
}

sub startPDF {
	if( !defined $PDF::root ){
		new PDFDoc( shift );
	}
}

sub startPDFDoc {
	return new PDFDoc( shift );
}

sub writePDF {
	$PDF::root->writePDF( shift );
}

sub writePDFDoc {
	$PDF::root->writePDF( shift );
}

sub importXML {
	return PDFDoc->importXML( shift );
}

sub reformatText {
	TextContent->reformatText( @_ );
}

sub tellColor {
	return Color::tellColor( @_ );
}

1;
