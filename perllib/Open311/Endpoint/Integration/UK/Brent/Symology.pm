package Open311::Endpoint::Integration::UK::Brent::Symology;

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology::Brent;

has jurisdiction_id => (
    is => 'ro',
    default => 'brent_symology',
);

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Symology::Brent'
);

sub event_action_event_type {
    my ($self, $args) = @_;
    return '';
}

sub process_service_request_args {
    my $self = shift;

    my $location = (delete $_[0]->{attributes}->{title}) || '';
    my @args = $self->SUPER::process_service_request_args(@_);
    my $response = $args[0];
    $response->{Location} = $location;

    return @args;
}

# Fetching updates will not currently work due to missing functions/setup

1;
