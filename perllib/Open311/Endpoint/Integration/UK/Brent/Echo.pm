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
        } elsif ($service_id == 274) {
            $args->{attributes}{"Clinical_BIN"} = 1;
            $args->{attributes}{"Clinical_BOX"} = 1;
        }
    } elsif ($request->{event_type} == 1159) {
        if ($args->{attributes}{Paid_Collection_Container_Type} == 2) {
            $args->{attributes}{"Bio_Sacks"} = 1;
            $args->{attributes}{Paid_Collection_Container_Quantity} = 9; # Bags
        }
    }

    return $request;
};

around post_service_request_update => sub {
    my ($orig, $class, $args) = @_;
    return $class->$orig($args) unless $args->{description};

    my $integ = $class->get_integration;
    my $event = $integ->GetEvent($args->{service_request_id});
    my $event_type = $integ->GetEventType($event->{EventTypeId});
    my $state_id = $event->{EventStateId};

    my $states = force_arrayref($event_type->{Workflow}->{States}, 'State');
    my $data;
    foreach (@$states) {
        my $core = $_->{CoreState};
        my $name = $_->{Name};
        $name =~ s/ +$//;
        $data->{states}{$_->{Id}} = {
            core => $core,
            name => $name,
        };
    }
    my $state = $data->{states}{$state_id};
    if ($state->{core} ne 'Closed' || $state->{name} ne 'Not Completed') {
        $args->{actiontype_id} = 334;
        $args->{datatype_id} = 112;
    }

    return $class->$orig($args);
};

sub force_arrayref {
    my ($res, $key) = @_;
    return [] unless $res;
    my $data = $res->{$key};
    return [] unless $data;
    $data = [ $data ] unless ref $data eq 'ARRAY';
    return $data;
}

1;
