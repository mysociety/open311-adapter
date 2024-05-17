=head1 NAME

Open311::Endpoint::Integration::UK::Merton::Passthrough - Merton Passthrough backend

=head1 SUMMARY

This is the Merton-specific Passthrough integration. It is a standard
Open311 server.

=cut

package Open311::Endpoint::Integration::UK::Merton::Passthrough;

use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'www.merton.gov.uk';
    $args{batch_service} = 1;
    return $class->$orig(%args);
};

1;
