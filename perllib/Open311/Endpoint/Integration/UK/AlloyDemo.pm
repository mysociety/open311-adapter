=head1 NAME

Open311::Endpoint::Integration::UK::AlloyDemo - Integration with Alloy demo instance

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::AlloyDemo;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'alloy_demo';
    return $class->$orig(%args);
};

1;
