#!/usr/bin/perl
use v5.10;
use strict;
use warnings;
use Socket;
use JSON::XS;
use Term::ReadKey;
use Data::Dumper;
use Cwd qw(getcwd);

my $ARG_name = "pserver";
my $ARG_socket;

# anything between +PC and -PC is for us, everything else is for them
my (@args) = @ARGV;
my @argv;
while (@args) {
    my $arg = shift @args;

    if ($arg eq '+PC') {
        while (@args || die("+PC must be closed by -PC\n") and (my $arg = shift(@args)) ne '-PC') {
            if ($arg eq '--name') {
                $ARG_name = shift(@args);
            } elsif ($arg eq '--socket') {
                $ARG_socket = shift(@args);
            }
        }
    } else {
        push(@argv,$arg);
    }
}
my $socket_name = $ARG_socket // "/tmp/pserver-$ENV{USER}/$ARG_name";

socket(SERVER,PF_UNIX,SOCK_STREAM,0);
connect(SERVER, sockaddr_un($socket_name));
sub input {
    my ($rin,$win,$ein);
    $rin = $win = $ein = '';
    vec($rin,fileno(SERVER),1) = 1;
    $ein = $rin | $win;
    my $select = select($rin,$win,$ein,0);
    $select;
}
sub command {
    my ($command) = shift;
    print SERVER encode_json($command)."\n";
}

my $oldfh = select(SERVER);
$| = 1;
select($oldfh);

command {ProgramName => "pserver"};
command {CommandLineArgs => \@argv};
my @env;
while (my ($k,$v) = each %ENV) {
    push @env,[$k,$v];
}
command {Environment=>\@env};
command {Capabilities=>['Dumb']};
command {WorkingDirectory=>getcwd};
ReadMode 4;
while (1) {
    while (input()) {
        my $input = decode_json(scalar <SERVER>);
        if (defined $input->{NormalOutput}) {
            print $input->{NormalOutput};
        } elsif (defined $input->{Exit}) {
            exit $input->{Exit};
        } elsif (defined $input->{ErrorOutput}) {
            print STDERR $input->{ErrorOutput};
        } else {
            print Dumper($input);
        }
    }
    my $key = ReadKey -1;
    if (defined $key) {
        command {KeyPress=>$key};
    }
}
END { ReadMode 0 }
