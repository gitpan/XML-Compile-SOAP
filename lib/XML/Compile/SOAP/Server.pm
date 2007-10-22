# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP::Server;
use vars '$VERSION';
$VERSION = '0.58';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

1;
