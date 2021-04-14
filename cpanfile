# setenv script
requires 'List::MoreUtils', '>= 0.425';
requires 'local::lib';
requires 'Class::Unload';

# Manual upgrades
requires 'IO::Socket::SSL', '2.056';

# Application
requires 'Cache::Memcached';
requires 'Carp';
requires 'Crypt::JWT';
requires 'Data::Dumper';
requires 'Data::Rx';
requires 'DateTime', '1.38';
requires 'DateTime::Format::Oracle';
requires 'DateTime::Format::W3CDTF', '>= 0.07';
# requires 'DBD::Oracle';
requires 'DBI';
requires 'Encode';
requires 'JSON::MaybeXS';
requires 'List::Util';
requires 'Module::Pluggable';
requires 'Moo';
requires 'Moo::Role';
requires 'MooX::HandlesVia';
requires 'namespace::autoclean';
requires 'Path::Tiny';
requires 'Scalar::Util';
requires 'SOAP::Lite';
requires 'Starman';
requires 'Text::CSV';
requires 'Text::CSV_XS';
requires 'Types::Standard';
requires 'XML::Simple';
requires 'Web::Simple';
requires 'YAML::XS';
requires 'YAML::Logic';
requires 'Log::Dispatch';
requires 'Tie::IxHash';

# Modules used by the test suite
requires 'LWP::Protocol::PSGI';
requires 'Module::Loaded';
requires 'Object::Tiny';
requires 'Test::Exception';
requires 'Test::LongString';
requires 'Test::MockModule';
requires 'Test::MockTime';
requires 'Test::More';
requires 'Test::Output';
