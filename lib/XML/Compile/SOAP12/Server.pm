# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use warnings;
use strict;

package XML::Compile::SOAP12::Server;
use vars '$VERSION';
$VERSION = '0.66';
use base 'XML::Compile::SOAP12', 'XML::Compile::SOAP::Server';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub prepareServer($)
{   my ($self, $server) = @_;
}

1;
