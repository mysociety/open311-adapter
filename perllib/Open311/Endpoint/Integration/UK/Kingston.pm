package Open311::Endpoint::Integration::UK::Kingston;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';
with 'Open311::Endpoint::Role::SLWP';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'kingston_echo';
    return $class->$orig(%args);
};

around check_for_data_value => sub {
    my ($orig, $class, $name, $args, $request, $parent_name) = @_;

    # Garden waste
    if ($args->{service_code} eq '1638') {
        my $method = $args->{attributes}{payment_method} || '';
        if ($name eq 'Payment Type') {
            return 3 if $method eq 'csc' || $method eq 'cheque'; # Telephone
        }
        if ($name eq 'Payment Method') {
            return 1 if $method eq 'csc' || $method eq 'cheque'; # Borough Phone Payment
            return 2 if $method eq 'credit_card'; # Borough Website Payment
        }
    }


    return $class->$orig($name, $args, $request, $parent_name);
};

1;
