package Open311::Endpoint::Integration::UK::Dudley;

# use SOAP::Lite +trace => [ qw/method debug/ ];

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology;

has jurisdiction_id => (
    is => 'ro',
    default => 'dudley_symology',
);

=head2 process_service_request_args

Maps the FixMyStreet report title to Symology's Location field, removing it
before shared processing so it is not also appended to the description.

=cut

sub process_service_request_args {
    my ($self, $request_args) = @_;

    my $location = delete $request_args->{attributes}->{title} || '';
    my ($request, @rest) =
        $self->SUPER::process_service_request_args($request_args);
    $request->{Location} = $location;

    return ($request, @rest);
}

1;
