package Open311::Endpoint::Integration::UK::Sutton;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'sutton_echo';
    return $class->$orig(%args);
};

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

1;
