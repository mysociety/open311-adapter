package Open311::Endpoint::Integration::UK::Bromley;

use DateTime;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bromley_echo';
    return $class->$orig(%args);
};

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

