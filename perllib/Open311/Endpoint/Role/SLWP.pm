package Open311::Endpoint::Role::SLWP;

use Moo::Role;

around check_for_data_value => sub {
    my ($orig, $class, $name, $args, $request, $parent_name) = @_;

    my $service = $args->{attributes}{service_id} || '';

    return 1 if $name eq 'Container Mix' && ($service eq '2241' || $service eq '2250' || $service eq '2246' || $service eq '3571');
    return 1 if $name eq 'Paper' && ($service eq '2240' || $service eq '2249' || $service eq '2632');
    return 1 if $name eq 'Food' && ($service eq '2239' || $service eq '2248');
    return 1 if $name eq 'Garden' && $service eq '2247';
    return 1 if $name eq 'Refuse Bag' && $service eq '2242';
    return 1 if $name eq 'Refuse Bin' && ($service eq '2238' || $service eq '2243' || $service eq '3576');

    my $method = $args->{attributes}{LastPayMethod} || '';
    return 2 if $name eq 'Payment Type' && $method eq 3; # DD
    return 3 if $name eq 'Payment Type' && $method eq 4; # 'cheque' (or phone)

    return $class->$orig($name, $args, $request, $parent_name);
};

around post_service_request_update => sub {
    my ($orig, $class, $args) = @_;
    return $class->$orig($args) unless $args->{description};

    if ($args->{description} =~ /Payment confirmed, reference (.*), amount (.*)/) {
        my ($ref, $amount) = ($1, $2);
        my $integ = $class->get_integration;
        my $event = $integ->GetEvent($args->{service_request_id});
        # Could GetEventType and loop through it all to find these IDs out but for just this seemed okay
        my $data = {
            id => 27409,
            childdata => [
                { id => 27410, value => $ref },
                { id => 27411, value => $amount },
            ],
        };
        $integ->UpdateEvent({ id => $event->{Id}, data => [ $data ] });
        $args->{description} = ''; # Blank out so nothing sent to Echo now
    }

    my $result = $class->$orig($args);

    return $result;
};

1;
