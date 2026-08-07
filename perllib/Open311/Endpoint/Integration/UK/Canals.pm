=head1 NAME

Open311::Endpoint::Integration::UK::Canals - Canals-specific parts of its Sugar integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Canals;

use Moo;
extends 'Open311::Endpoint::Integration::Sugar';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'canals_sugar';
    return $class->$orig(%args);
};

1;
