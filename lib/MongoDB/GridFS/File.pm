#
#  Copyright 2009 10gen, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::GridFS::File;
our $VERSION = '0.22';

# ABSTRACT: A Mongo GridFS file

use Any::Moose;
use MongoDB::GridFS;

=head1 SYNOPSIS

    use MongoDB::GridFS::File;

    my $outfile = IO::File->new("outfile", "w");
    my $file = $grid->find_one;
    $file->print($outfile);

=cut

has _grid => (
    is       => 'ro',
    isa      => 'MongoDB::GridFS',
    required => 1,
);

=attr info

A hash of info information saved with this file.

=cut

has info => (
    is => 'ro',
    isa => 'HashRef',
    required => 1,
);


=method print ($fh, $length, $offset)

    $written = $file->print($fh, 50, 200);

Writes the number of bytes specified from the offset specified 
to the given file handle.  If no C<$length> or C<$offset> are
given, the entire file is written to C<$fh>.  Returns the number
of bytes written.

=cut

sub print {
    my ($self, $fh, $length, $offset) = @_;
    $offset ||= 0;
    $length ||= 0;
    my ($written, $pos) = (0, 0);
    my $start_pos = $fh->getpos();

    $self->_grid->chunks->ensure_index(["n"]);

    my $cursor = $self->_grid->chunks->query({"files_id" => $self->info->{"_id"}})->sort({"n" => 1});

    while ((my $chunk = $cursor->next) && (!$length || $written < $length)) {
        my $len = length $chunk->{'data'};

        # if we are cleanly beyond the offset
        if (!$offset || $pos >= $offset) {
            if (!$length || $written + $len < $length) {
                $fh->print($chunk->{"data"});
                $written += $len;
                $pos += $len;
            }
            else {
                $fh->print(substr($chunk->{'data'}, 0, $length-$written));
                $written += $length-$written;
                $pos += $length-$written;
            }
            next;
        }
        # if the offset goes to the middle of this chunk
        elsif ($pos + $len > $offset) {
            # if the length of this chunk is smaller than the desired length
            if (!$length || $len <= $length-$written) {
                $fh->print(substr($chunk->{'data'}, $offset-$pos, $len-($offset-$pos)));
                $written += $len-($offset-$pos);
                $pos += $len-($offset-$pos);
            }
            else {
                $fh->print(substr($chunk->{'data'}, $offset-$pos, $length));
                $written += $length;
                $pos += $length;
            }
            next;
        }
        # if the offset is larger than this chunk
        $pos += $len;
    }
    $fh->setpos($start_pos);
    return $written;
}

1;

