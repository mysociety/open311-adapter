package Open311::Endpoint::Role::ConfigFile;
use Moo::Role;
use Path::Tiny 'path';
use Carp 'croak';
use YAML::XS qw(LoadFile Load);
use Types::Standard qw( Maybe Str );

has config_filename => (
    is => 'ro',
    default => '',
);

has config_file => (
    is => 'ro',
    isa => Maybe[Str],
);

around BUILDARGS => sub {
    my $next = shift;
    my $class = shift;
    my %args = @_;

    die unless $args{jurisdiction_id}; # Must have one by here
    my $file;
    if ($args{config_filename}) {
        $file = $args{config_filename};
    } else {
        $args{config_filename} = $args{jurisdiction_id};
        $file = "council-$args{config_filename}.yml";
    }
    $args{config_file} //= path(__FILE__)->parent(5)->realpath->child("conf/$file")->stringify;

    if (my $config_data = $args{config_data}) {
        my $config = Load($config_data) or croak "Couldn't load config from string";
        return $class->$next(%$config, %args);
    } elsif (my $config_file = $args{config_file}) {
        my $cfg = path($config_file);

        return $class->$next(%args) if !$cfg->is_file && $ENV{TEST_MODE};
        croak "$config_file is not a file" unless $cfg->is_file;

        my $config = LoadFile($cfg) or croak "Couldn't load config from $config_file";
        return $class->$next(%$config, %args);
    }
    else {
        return $class->$next(%args);
    }
};

1;
