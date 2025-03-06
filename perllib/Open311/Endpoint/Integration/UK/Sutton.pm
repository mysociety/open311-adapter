=head1 NAME

Open311::Endpoint::Integration::UK::Sutton

=head1 DESCRIPTION

The Sutton integration. As well as the boilerplate, and setting it as an Echo
integration, this makes sure the right "Payment Taken By" option is chosen for
bulky collections.

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

around check_for_data_value => sub {
    my ($orig, $class, $name, $args, $request, $parent_name) = @_;

    # Bulky items
    if ($args->{service_code} eq '1636') {
        my $method = $args->{attributes}{payment_method} || '';
        if ($method eq 'csc' || $method eq 'cheque') {
            return 1 if $name eq 'Payment Taken By'; # Council
        } elsif ($method eq 'credit_card') {
            return 2 if $name eq 'Payment Taken By'; # Veolia
        }
    }

    # Garden waste
    if ($args->{service_code} eq '1638') {
        my $method = $args->{attributes}{payment_method} || '';
        return 3 if $name eq 'Payment Type' && $method eq 'cheque'; # Telephone
    }

    return $class->$orig($name, $args, $request, $parent_name);
};

has cancel_actiontype_id => ( is => 'ro', default => 8 );

1;
