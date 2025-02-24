=head1 NAME

Open311::Endpoint::Integration::UK::Hackney::Arcus - Hackney passthrough for the Arcus backend

=head1 SUMMARY

This is the Hackney-specific Arcus integration. It is a standard
Open311 server apart from it uses a different endpoint for updates.

=cut

package Open311::Endpoint::Integration::UK::Hackney::Arcus;

use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hackney_arcus';
    return $class->$orig(%args);
};

1;
