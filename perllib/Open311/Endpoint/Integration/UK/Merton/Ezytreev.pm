=head1 NAME

Open311::Endpoint::Integration::UK::Merton::Ezytreev - Merton-specific parts of its Ezytreev integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Merton::Ezytreev;

use Moo;
extends 'Open311::Endpoint::Integration::Ezytreev';

has jurisdiction_id => (
    is => 'ro',
    default => 'merton_ezytreev',
);

=head2 process_service_request_args

Adds two additional fields:
* 'EnquiryMethod' - set to 'F'
* 'EnquiryOrigion' [sic] - set to 'FM'

=cut

sub process_service_request_args {
    my ($self, $crm_xref, $service, $args) = @_;
    my $payload = $self->SUPER::process_service_request_args($crm_xref, $service, $args);
    $payload->{EnquiryMethod} = 'F';
    $payload->{EnquiryOrigion} = 'FM';  # sic
    return $payload;
}

=head2 get_service_requests

Doesn't implement service request fetching.

=cut

sub get_service_requests { return (); }

=head2 post_service_request_update

Doesn't implement service request update sending.

=cut

sub post_service_request_update { }

__PACKAGE__->run_if_script;
