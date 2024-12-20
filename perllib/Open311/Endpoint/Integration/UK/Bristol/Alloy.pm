=head1 NAME

Open311::Endpoint::Integration::UK::Bristol::Alloy - Bristol-specific parts of its Alloy integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Bristol::Alloy;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bristol_alloy';
    return $class->$orig(%args);
};

1;
