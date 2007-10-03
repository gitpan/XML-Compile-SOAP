# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP::Server;
use vars '$VERSION';
$VERSION = '0.55';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub new(@) { panic "protocol server not implemented" }
sub init($) { shift }

1;
