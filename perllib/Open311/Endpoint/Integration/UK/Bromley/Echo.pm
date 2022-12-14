=head1 NAME

Open311::Endpoint::Integration::UK::Bromley::Echo - Bromley-specific Echo backend configuration

=head1 SYNOPSIS

Bromley specifics for its Echo backend

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Bromley::Echo;

use DateTime;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bromley_echo';
    return $class->$orig(%args);
};

=head2 process_service_request_args

If we are sending an assisted collection event, we need to set some special
parameters. When adding an assisted collection, we set the action and
start/end/review dates; when removing, we set the actino and end date.

=cut

around process_service_request_args => sub {
    my ($orig, $class, $args) = @_;
    my $request = $class->$orig($args);
    # Assisted collection
    if ($request->{event_type} == 2149) {
        my $date = DateTime->today(time_zone => "Europe/London");
        if ($args->{service_code} eq "2149-add") {
            $args->{attributes}{"Assisted_Action"} = 1;
            $args->{attributes}{"Assisted_Start_Date"} = $date->strftime("%d/%m/%Y");
            $args->{attributes}{"Assisted_End_Date"} = "01/01/2050";
            $date->add(years => 2);
            $args->{attributes}{"Review_Date"} = $date->strftime("%d/%m/%Y");
        } elsif ($args->{service_code} eq "2149-remove") {
            $args->{attributes}{"Assisted_Action"} = 2;
            $args->{attributes}{"Assisted_End_Date"} = $date->strftime("%d/%m/%Y");
        }
    }
    return $request;
};

1;

