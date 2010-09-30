# Copyrights 2007-2010 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Extension;
use vars '$VERSION';
$VERSION = '2.17';

use Log::Report 'xml-compile-soap';

my @ext;


sub new($@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my $self = shift;
    trace "loading extension ".ref $self;
    push @ext, $self;
    $self;
}


sub wsdl11Init($$)
{   ref shift and return;
    $_->wsdl11Init(@_) for @ext;
}


sub soap11OperationInit($@)
{   ref shift and return;
    $_->soap11OperationInit(@_) for @ext;
}


sub soap11ClientWrapper($$@)
{   ref shift and return $_[1];
    my ($op, $call) = (shift, shift);
    $call = $_->soap11ClientWrapper($op, $call, @_) for @ext;
    $call;
}

1;
