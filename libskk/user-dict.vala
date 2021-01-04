/*
 * Copyright (C) 2011-2018 Daiki Ueno <ueno@gnu.org>
 * Copyright (C) 2011-2018 Red Hat, Inc.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
using Gee;

namespace Skk {
    /**
     * File based implementation of Dict with write access.
     */
    public class UserDict : Dict {
        void load () throws SkkDictError, GLib.IOError {
            uint8[] contents;
            try {
                file.load_contents (null, out contents, out etag);
            } catch (GLib.Error e) {
                throw new SkkDictError.NOT_READABLE ("can't load contents");
            }
            var memory = new MemoryInputStream.from_data (contents, g_free);
            var data = new DataInputStream (memory);

            string? line = null;
            size_t length;
            line = data.read_line (out length);
            if (line == null) {
                return;
            }

            var coding = EncodingConverter.extract_coding_system (line);
            if (coding != null) {
                try {
                    var _converter = new EncodingConverter.from_coding_system (
                        coding);
                    if (_converter != null) {
                        converter = _converter;
                    }
                } catch (Error e) {
                    warning ("can't create converter from coding system %s: %s",
                             coding, e.message);
                }
                // proceed to the next line
                line = data.read_line (out length);
                if (line == null) {
                    return;
                }
            }

            bool okuri = false;
            while (line != null) {
                if (line.has_prefix (";; okuri-ari entries.")) {
                    okuri = true;
                    break;
                }
                line = data.read_line (out length);
                if (line == null) {
                    break;
                }
            }
            if (okuri == false) {
                throw new SkkDictError.MALFORMED_INPUT (
                    "no okuri-ari boundary");
            }

            while (line != null) {
                line = data.read_line (out length);
                if (line == null) {
                    break;
                }
                if (line.has_prefix (";; okuri-nasi entries.")) {
                    okuri = false;
                    continue;
                }
                try {
                    line = converter.decode (line);
                } catch (GLib.Error e) {
                    throw new SkkDictError.MALFORMED_INPUT (
                        "can't decode line %s: %s", line, e.message);
                }
                int index = line.index_of (" ");
                if (index < 1) {
                    throw new SkkDictError.MALFORMED_INPUT (
                        "can't extract midasi from line %s",
                        line);
                }

                string midasi = line[0:index];
                string candidates_str = line[index + 1:line.length];
                if (!candidates_str.has_prefix ("/") ||
                    !candidates_str.has_suffix ("/")) {
                    throw new SkkDictError.MALFORMED_INPUT (
                        "can't parse candidates list %s",
                        candidates_str);
                }

                var candidates = split_candidates (midasi,
                                                   okuri,
                                                   candidates_str);
                var list = new LinkedList<Candidate> ();
                foreach (var c in candidates) {
                    list.add (c);
                }

                var new_entry = new UserDictEntry (midasi, list);
                if (okuri) {
                    okuri_ari_entries.prepend (new_entry);
                } else {
                    okuri_nasi_entries.prepend (new_entry);
                }
            }

            okuri_ari_entries.reverse ();
            okuri_nasi_entries.reverse ();
        }

        /**
         * {@inheritDoc}
         */
        public override void reload () throws GLib.Error {
#if VALA_0_16
            string attributes = FileAttribute.ETAG_VALUE;
#else
            string attributes = FILE_ATTRIBUTE_ETAG_VALUE;
#endif
            FileInfo info = file.query_info (attributes,
                                             FileQueryInfoFlags.NONE);
            if (info.get_etag () != etag) {
                okuri_ari_entries = null;
                okuri_nasi_entries = null;
                try {
                    load ();
                } catch (SkkDictError e) {
                    warning ("error parsing user dictionary %s: %s",
                             file.get_path (), e.message);
                } catch (GLib.IOError e) {
                    warning ("error reading user dictionary %s: %s",
                             file.get_path (), e.message);
                }
            }
        }

        void write_entries (StringBuilder builder,
                            SList<UserDictEntry> entries)
        {
            foreach (var entry in entries) {
                var line = "%s %s\n".printf (
                    entry.midasi,
                    join_candidates (entry.candidates.to_array ()));
                builder.append (line);
            }
        }

        /**
         * {@inheritDoc}
         */
        public override void save () throws GLib.Error {
            var builder = new StringBuilder ();
            var coding = converter.get_coding_system ();
            if (coding != null) {
                builder.append (";;; -*- coding: %s -*-\n".printf (coding));
            }

            builder.append (";; okuri-ari entries.\n");
            write_entries (builder, okuri_ari_entries);

            builder.append (";; okuri-nasi entries.\n");
            write_entries (builder, okuri_nasi_entries);

            var contents = converter.encode (builder.str);
            DirUtils.create_with_parents (Path.get_dirname (file.get_path ()),
                                          448);
#if VALA_0_16
            file.replace_contents (contents.data,
                                   etag,
                                   false,
                                   FileCreateFlags.PRIVATE,
                                   out etag);
#else
            file.replace_contents (contents,
                                   contents.length,
                                   etag,
                                   false,
                                   FileCreateFlags.PRIVATE,
                                   out etag);
#endif
        }

        /**
         * {@inheritDoc}
         */
        public override Candidate[] lookup (string midasi, bool okuri = false) {
            // Arrays are not supported as generic type arguments
            Candidate[] ret = new Candidate[0];
            with_entries<void> (okuri, (ref entries) => {
                foreach (var entry in entries) {
                    if (entry.midasi == midasi) {
                        ret = entry.candidates.to_array ();
                        break;
                    }
                }
            });
            return ret;
        }

        /**
         * {@inheritDoc}
         */
        public override string[] complete (string midasi) {
            Gee.List<string> completion = new ArrayList<string> ();

            foreach (var entry in okuri_nasi_entries) {
                if (entry.midasi.has_prefix (midasi) &&
                    entry.midasi != midasi)
                {
                    completion.add (entry.midasi);
                }
            }

            return completion.to_array ();
        }

        /**
         * {@inheritDoc}
         */
        public override bool select_candidate (Candidate candidate) {
            return with_entries<bool> (candidate.okuri, (ref entries) => {
                foreach (var entry in entries) {
                    if (entry.midasi == candidate.midasi) {
                        var entry_modified = entry.select (candidate);
                        if (entries.data != entry) {
                            entries.remove (entry);
                            entries.prepend (entry);
                            return true;
                        }
                        return entry_modified;
                    }
                }

                var new_entry = new UserDictEntry.from_candidate (candidate);
                entries.prepend (new_entry);
                return true;
            });
        }

        /**
         * {@inheritDoc}
         */
        public override bool purge_candidate (Candidate candidate) {
            return with_entries<bool> (candidate.okuri, (ref entries) => {
                var modified = false;

                foreach (var entry in entries) {
                    if (entry.midasi == candidate.midasi) {
                        var purged = entry.purge (candidate);
                        if (purged && entry.candidates.is_empty) {
                            entries.remove (entry);
                        }
                        modified |= purged;
                    }
                }
                return modified;
            });
        }

        /**
         * {@inheritDoc}
         */
        public override bool read_only {
            get {
                return false;
            }
        }

        File file;
        string etag;
        EncodingConverter converter;

        /**
         * Ordered okuri ari entries;
         * Head is most recent selected candidate.
         */
        SList<UserDictEntry> okuri_ari_entries = null;

        /**
         * Ordered okuri nasi entries;
         * Head is most recent selected candidate.
         */
        SList<UserDictEntry> okuri_nasi_entries = null;

        delegate T WithEntries<T> (ref SList<UserDictEntry> entries);

        T with_entries<T> (bool okuri, WithEntries<T> f) {
            if (okuri) {
                return f (ref okuri_ari_entries);
            } else {
                return f (ref okuri_nasi_entries);
            }
        }

        /**
         * Create a new UserDict.
         *
         * @param path a path to the file
         * @param encoding encoding of the file (default UTF-8)
         *
         * @return a new UserDict
         * @throws GLib.Error if opening the file is failed
         */
        public UserDict (string path,
                         string encoding = "UTF-8") throws GLib.Error
        {
            this.file = File.new_for_path (path);
            this.etag = "";
            this.converter = new EncodingConverter (encoding);
            // user dictionary may not exist for the first time
            if (FileUtils.test (path, FileTest.EXISTS)) {
                reload ();
            }
        }

        ~UserDict () {
            okuri_ari_entries = null;
            okuri_nasi_entries = null;
        }
    }

    private class UserDictEntry {
        public string midasi;
        public LinkedList<Candidate> candidates;

        /**
         * Select the candidate in this candidates; If this candidates
         * does not have the candidate at head, bring it to head.
         *
         * @return `true` if modified this candidates, `false` otherwise
         */
        public bool select (Candidate candidate) {
            if (!candidates.is_empty
                && candidates.first ().text == candidate.text) {
                return false;
            }

            var iter = candidates.iterator ();
            while (iter.next ()) {
                var c = iter.get ();
                if (c.text == candidate.text) {
                    iter.remove ();
                }
            }
            candidates.insert (0, candidate);
            return true;
        }

        /**
         * Purge the candidate in this candidates.
         */
        public bool purge (Candidate candidate) {
            var purged = false;
            var iter = candidates.iterator ();
            while (iter.next ()) {
                var c = iter.get ();
                if (c.text == candidate.text) {
                    iter.remove ();
                    purged = true;
                }
            }
            return purged;
        }

        public UserDictEntry (string midasi,
                              LinkedList<Candidate> candidates)
        {
            this.midasi = midasi;
            this.candidates = candidates;
        }

        public UserDictEntry.from_candidate (Candidate candidate) {
            this.midasi = candidate.midasi;
            this.candidates = new LinkedList<Candidate> ();
            this.candidates.add (candidate);
        }
    }
}
