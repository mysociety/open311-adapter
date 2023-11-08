=head1 NAME

Open311::Endpoint::Integration::UK::Bromley::Passthrough - Bromley Passthrough backend

=head1 SUMMARY

This is the Bromley-specific Passthrough integration. It is a standard
Open311 server apart from it uses a different endpoint for updates.

=cut

package Open311::Endpoint::Integration::UK::Bromley::Passthrough;

use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'www.bromley.gov.uk';
    return $class->$orig(%args);
};

has '+updates_url' => ( default => 'update.xml' );

1;
