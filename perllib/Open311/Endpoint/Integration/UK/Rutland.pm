package Open311::Endpoint::Integration::UK::Rutland;
use parent 'Open311::Endpoint::Integration::SalesForce::Rutland';

use Moo;

has jurisdiction_id => (
    is => 'ro',
    default => 'rutland',
);

sub reverse_status_mapping {
    my ($self, $status) = @_;

    my %valid_status = map { my $no_spaces  = $_; $no_spaces =~ s/\s+/_/g; $_ => $no_spaces; } (
        'open', 'investigating', 'in progress', 'planned', 'action scheduled',
        'no further action', 'not councils responsibility', 'duplicate', 'internal referral',
        'fixed', 'closed',
    );

    $valid_status{'not responsible'} = 'not_councils_responsibility';

    return $valid_status{lc($status)} || 'open';
}

1;
