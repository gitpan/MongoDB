#!perl

use strict;
use warnings;

# This test was generated by inc::CheckJiraInChanges

use Test::More tests => 1;

my @commits = split /\n/, <<'EOC';
9e6a5c5 PERL-376 Reorder Moose/MongoDB module loading
1f36fb8 PERL-355 use random test database names for parallel testing

EOC

my %ticket_map;
for my $commit ( @commits ) {
    for my $ticket ( $commit =~ /PERL-(\d+)/g ) {
        $ticket_map{$ticket} ||= [];
        push @{$ticket_map{$ticket}}, $commit;
    }
}

# grab Changes lines from new version to next un-indented line
open my $fh, "<:encoding(UTF-8)", "Changes";
my @content = grep { /^v0.704.2.0(?:\s+|$)/ ... /^\S/ } <$fh>;

# drop the version line
shift @content;

# drop unindented last line and trailing blank lines
pop @content while ( @content && $content[-1] =~ /^(?:\S|\s*$)/ );

my $changelog = join(" ", @content);

my @bad;
for my $ticket ( keys %ticket_map ) {
    if ( index( $changelog, "PERL-$ticket" ) < 0 ) {
       push @bad, $ticket;
    }
}

if ( !@commits ) {
    pass("No commits with Jira tickets");
}
else {
    ok( ! scalar @bad, "Jira tickets in Changes")
        or diag "Jira tickets missing:\n"
        . join("\n", map { "  * $_" } map { @{$ticket_map{$_}} } sort { $a <=> $b } @bad );
}
