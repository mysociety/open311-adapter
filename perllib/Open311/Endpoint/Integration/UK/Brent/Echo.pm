package Open311::Endpoint::Integration::UK::Brent::Echo;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'brent_echo';
    return $class->$orig(%args);
};

around process_service_request_args => sub {
    my ($orig, $class, $args) = @_;
    my $request = $class->$orig($args);

    # Missed collection
    if ($request->{event_type} == 2891) {
        my $service_id = $args->{attributes}{service_id};
        if ($service_id == 262 || $service_id == 267 || $service_id == 263 || $service_id == 264) {
            $args->{attributes}{"Refuse_BIN"} = 1;
            $args->{attributes}{"Refuse_BAG"} = 1;
        } elsif ($service_id == 265 || $service_id == 266 || $service_id == 268 || $service_id == 269) {
            $args->{attributes}{"Mixed_Dry_Recycling_BIN"} = 1;
            $args->{attributes}{"Mixed_Dry_Recyling_BOX"} = 1;
        } elsif ($service_id == 316 || $service_id == 271) {
            $args->{attributes}{"Food_CADDY"} = 1;
            $args->{attributes}{"Food_BIN"} = 1;
        } elsif ($service_id == 317) {
            $args->{attributes}{"Garden_BIN"} = 1;
            $args->{attributes}{"Garden_BAG"} = 1;
        }
    }

    return $request;
};

1;
