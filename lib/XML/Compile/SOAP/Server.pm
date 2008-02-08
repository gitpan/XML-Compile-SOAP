# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.03.
use warnings;
use strict;

package XML::Compile::SOAP::Server;
use vars '$VERSION';
$VERSION = '0.67';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';


sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }


sub compileHandler(@)
{   my ($self, %args) = @_;

    my $decode = $args{decode};
    my $encode = $args{encode} || $self->compileMessage('SENDER');
    my $name   = $args{name}
        or error __x"each server handler requires a name";

    # even without callback, we will validate
    my $callback = $args{callback} || $self->faultNotImplemented($name);

    sub
    {   my ($xmlin) = @_;
        my $doc  = XML::LibXML::Document->new('1.0', 'UTF-8');
        my $data;

        if($decode)
        {   $data = try { $decode->($xmlin) };
            if($@)
            {   my $exception = $@->wasFatal;
                $exception->throw(reason => 'info');
                $data = $self->faultValidationFailed($doc, $name,
                    $exception->message->toString);
            }
        }
        else
        {   $data = $xmlin;
        }

        my $answer = $callback->($self, $doc, $data);

        return $answer
            if UNIVERSAL::isa($answer, 'XML::LibXML::Document');

        $encode->($doc, $answer);
    };
}

1;
