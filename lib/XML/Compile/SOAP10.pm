# Copyrights 2007-2012 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP10;
use vars '$VERSION';
$VERSION = '2.26';

use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util       qw/pack_type unpack_type SCHEMA2001/;
use XML::Compile::SOAP::Util qw/:soap11/;

use XML::Compile::SOAP10::Operation ();
use XML::Compile::SOAP11;  # for schemas


sub new($@)
{   my $class = shift;
    error __x"I have no idea how SOAP pure HTTP-GET and -POST are supposed to work. Please show me the spec";
}

1;
