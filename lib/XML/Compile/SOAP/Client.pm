# Copyrights 2007 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use warnings;
use strict;

package XML::Compile::SOAP::Client;
use vars '$VERSION';
$VERSION = '0.63';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

#------------------------------------------------


sub compileCall(@)
{   my ($self, %args) = @_;

    my $kind = $args{kind} || 'request-response';
    $kind eq 'request-response'
        or error __x"soap call type {kind} not supported", kind => $kind;

    my $encode = $args{request}
        or error __x"call requires a request encoder";

    my $decode = $args{response}
        or error __x"call requires a response decoder";

    my $transport = $args{transport}
        or error __x"call requires a transport handler";

    sub
    { my $request  = $encode->(@_);
      my ($response, $trace) = $transport->($request);
      my $answer   = $decode->($response);
      wantarray ? ($answer, $trace) : $answer;
    };
}

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
