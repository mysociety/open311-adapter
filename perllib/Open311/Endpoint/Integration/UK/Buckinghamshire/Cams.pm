=head1 NAME

Open311::Endpoint::Integration::UK::Buckinghamshire::Cams - Buckinghamshire-specific parts of its Cams integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Buckinghamshire::Cams;

use Moo;
extends 'Open311::Endpoint::Integration::Cams';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'buckinghamshire_cams';
    return $class->$orig(%args);
};

1;
