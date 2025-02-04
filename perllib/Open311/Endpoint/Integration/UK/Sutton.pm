=head1 NAME

Open311::Endpoint::Integration::UK::Sutton

=head1 DESCRIPTION

The Sutton integration. Boilerplate, and setting it as an Echo integration.

=cut

package Open311::Endpoint::Integration::UK::Sutton;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';
with 'Open311::Endpoint::Role::SLWP';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'sutton_echo';
    return $class->$orig(%args);
};

has cancel_actiontype_id => ( is => 'ro', default => 8 );

1;
