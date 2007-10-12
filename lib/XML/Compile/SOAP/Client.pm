# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.02.
use warnings;
use strict;

package XML::Compile::SOAP::Client;
use vars '$VERSION';
$VERSION = '0.56';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

#------------------------------------------------


my $fake_server;
sub fakeServer()
{   return $fake_server if @_==1;

    my $server = $_[1];
    defined $server
        or return $fake_server = undef;

    ref $server && $server->isa('XML::Compile::SOAP::Tester')
        or error __x"fake server isn't a XML::Compile::SOAP::Tester";

    $fake_server = $server;
}

1;
