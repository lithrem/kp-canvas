FROM fedora:23
MAINTAINER Lithrem <lithrem@kororaproject.org>


RUN dnf -y clean all
RUN dnf -y update
RUN dnf -y install cpan \
  perl-Time-Piece \
  perl-DBI  \
  perl-Test-Simple \
  perl-DBD-Pg \
  perl-List-MoreUtils \
  perl-Text-Balanced \
  perl-MIME-Lite
RUN cpan -i Mojolicious
RUN cpan -i Mojo::Pg
ADD . /srv/www

EXPOSE 8080

WORKDIR /srv/www/upstream/server/

CMD hypnotoad -f ./canvasd

