=head1 NAME

Open311::Endpoint::Role::SLWP

=head1 DESCRIPTION

Special handling for both Kingston and Sutton. This makes sure the right
container types are picked for requests, and that the right payment options are
chosen for garden/bulky.

=cut

package Open311::Endpoint::Role::SLWP;

use utf8;
use Moo::Role;

around check_for_data_value => sub {
    my ($orig, $class, $name, $args, $request, $parent_name) = @_;

    my $service = $args->{attributes}{service_id} || '';

    return 1 if $name eq 'Container Mix' && ($service eq '2241' || $service eq '2250' || $service eq '2246' || $service eq '3571');
    return 1 if $name eq 'Paper' && ($service eq '2240' || $service eq '2249' || $service eq '2632');
    return 1 if $name eq 'Food' && ($service eq '2239' || $service eq '2248');
    return 1 if ($name eq 'Garden' || $name eq 'Garden Waste ') && $service eq '2247'; # Attribute has a space at the end
    return 1 if $name eq 'Refuse Bag' && $service eq '2242';
    return 1 if $name eq 'Refuse Bin' && ($service eq '2238' || $service eq '2243' || $service eq '3576');

    # Bulky items
    if ($args->{service_code} eq '1636') {
        # Default in configuration is Payment Type 1 (Card), Payment Method 2 (Website)
        my $method = $args->{attributes}{payment_method} || '';
        return 2 if $name eq 'Payment Type' && $method eq 'cheque'; # Cheque
        if ($name eq 'Payment Method') {
            return 1 if $method eq 'csc' || $method eq 'cheque'; # Borough Phone Payment
            return 2 if $method eq 'credit_card'; # Borough Website Payment
        }
    }

    return $class->$orig($name, $args, $request, $parent_name);
};

around post_service_request_update => sub {
    my ($orig, $class, $args) = @_;
    return $class->$orig($args) unless $args->{description};

    if (my $payments = $args->{attributes}{payments}) {
        my @data = split /\|/, $payments;
        my @payments;
        for (my $i=0; $i<@data; $i+=2) {
            push @payments, { ref => $data[$i], amount => $data[$i+1] }
        }
        $class->update_event_payment($args, \@payments);
    } elsif ($args->{description} =~ /Payment confirmed, reference (.*), amount (.*)/) {
        my ($ref, $amount) = ($1, $2);
        $class->update_event_payment($args, [ { ref => $ref, amount => $amount } ]);
    }

    if ($args->{description} =~ /Booking cancelled/ || $args->{attributes}{booking_cancelled}) {
        $args->{actiontype_id} = $class->cancel_actiontype_id;
        $args->{datatype_id} = 0;
    }

    my $result = $class->$orig($args);

    return $result;
};

1;
