=head1 NAME

Open311::Endpoint::Integration::UK::Merton::Echo - Merton-specific Echo backend configuration

=head1 SYNOPSIS

Merton specifics for its Echo backend

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Merton::Echo;

use utf8;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';
with 'Open311::Endpoint::Role::SLWP';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'merton_echo';
    return $class->$orig(%args);
};

has cancel_actiontype_id => ( is => 'ro', default => 8 );

has bulky_amend_actiontype_id => ( is => 'ro', default => 12 );

=head2 process_service_request_args

If we are sending an assisted collection event, we need to set some special
parameters.

=cut

around process_service_request_args => sub {
    my ($orig, $class, $args) = @_;
    my $request = $class->$orig($args);
    # Assisted collection
    if ($args->{service_code} eq "1565-add") {
        $args->{attributes}{"Add_to_Assist"} = 1;
    } elsif ($args->{service_code} eq "1565-remove") {
        $args->{attributes}{"Remove_from_Assist"} = 1;
    }
    return $request;
};

1;
