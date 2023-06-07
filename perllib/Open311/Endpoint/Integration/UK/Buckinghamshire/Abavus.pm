=head1 NAME

Open311::Endpoint::Integration::UK::Buckinghamshire::Abavus - Buckinghamshire-specific parts of its Abavus integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Buckinghamshire::Abavus;

use Moo;
extends 'Open311::Endpoint::Integration::Abavus';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'buckinghamshire_abavus';
    return $class->$orig(%args);
};

1;
