# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP11::Client;
use vars '$VERSION';
$VERSION = '2.15';

use base 'XML::Compile::SOAP11','XML::Compile::SOAP::Client';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util qw/unpack_type/;


1;
