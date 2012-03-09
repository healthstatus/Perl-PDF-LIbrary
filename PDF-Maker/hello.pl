# Run as: perl hello.pl
# A file named "hello.pdf" will be created, show text in center of page.

use PDF;

my $doc = new PDFDoc( );
$doc->newPage( { Paddings => '20', Size => 'LetterR' } );
$doc->newTextBox(
	$doc->getCell( 1, 1, 1 ),
	"Hello, world!",
	{ FontSize => 40, FontColor => 'red', BorderWidth => 2, TextJustify => 'Center', VerticalAlign => 'Middle' }
);
$doc->writePDF( 'hello.pdf' );
