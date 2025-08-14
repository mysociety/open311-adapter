=head1 NAME

Open311::Endpoint::Integration::UK::Merton::Echo - Merton-specific Echo backend configuration

=head1 SYNOPSIS

Merton specifics for its Echo backend

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Merton::Echo;

use utf8;
use DateTime;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';
with 'Open311::Endpoint::Role::SLWP';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'merton_echo';
    return $class->$orig(%args);
};

has cancel_actiontype_id => ( is => 'ro', default => 8 );

=head2 process_service_request_args

If we are sending an assisted collection event, we need to set some special
parameters.

=cut

around process_service_request_args => sub {
    my ($orig, $class, $args) = @_;
    my $request = $class->$orig($args);
    # Assisted collection
    if ($request->{event_type} == 3200) {
        my $date = DateTime->today(time_zone => "Europe/London");
        if ($args->{service_code} eq "3200-add") {
            $args->{attributes}{"Action"} = 1;
            $args->{attributes}{"Start_Date"} = $date->strftime("%d/%m/%Y");
        } elsif ($args->{service_code} eq "3200-remove") {
            $args->{attributes}{"Action"} = 2;
            $args->{attributes}{"End_Date"} = $date->strftime("%d/%m/%Y");
        }
    }
    return $request;
};

1;
