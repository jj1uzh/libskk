/*
 * Copyright (C) 2021 Futa MIYACHI <miyachf@gmail.com>
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

    class Completer : Object {

        unowned Gee.List<Dict> dicts;
        string midasi;
        internal CompletionState state {
            get; private set; default = CompletionState.Uninitialized;
        }
        internal int index {
            get; private set; default = -1;
        }
        internal Gee.List<string> completions {
            get; private set; default = new ArrayList<string> ();
        }
        Gee.Set<string> completion_set = new HashSet<string> ();

        internal signal void expanded ();
        internal signal void cleared ();

        internal void clear_if_initialized () {
            if (state.is_initialized ())
                clear ();
        }

        internal void clear () {
            dicts = null;
            state = CompletionState.Uninitialized;
            midasi = null;
            index = -1;
            completions.clear ();
            completion_set.clear ();
            cleared ();
        }

        [CCode (type="inline")]
        bool add_completion (string candidate) {
            if (completion_set.add (candidate)) {
                completions.add (candidate);
                return true;
            } else {
                return false;
            }
        }

        bool complete_with_user_dicts () {
            var actually_expanded = false;
            foreach (var dict in dicts) {
                if (! (dict is UserDict)) continue;
                foreach (var candidate in dict.complete (midasi)) {
                    actually_expanded |= add_completion (candidate);
                }
            }
            return actually_expanded;
        }

        void complete_with_user_dicts_with_limit (int size) {
            var cur_size = 0;
            foreach (var dict in dicts) {
                if (! (dict is UserDict)) continue;
                var userdict = dict as UserDict;
                var candidates = userdict.complete_with_limit (midasi, 
                                                               size - cur_size);
                foreach (var candidate in candidates) {
                    if (add_completion (candidate))
                        cur_size += 1;
                }
                if (cur_size >= size) return;
            }
        }

        void complete_with_non_user_dicts () {
            var comps = new LinkedList<string> ();
            foreach (var dict in dicts) {
                if (dict is UserDict) continue;
                foreach (var candidate in dict.complete (midasi)) {
                    comps.add (candidate);
                }
            }
            comps.sort ();
            foreach (var candidate in comps) {
                add_completion (candidate);
            }
        }

        void expand_completion () {
            switch (state) {
            case CompletionState.Full, CompletionState.Uninitialized:
                break;
            case CompletionState.None, CompletionState.UserDictWithLimit:
                var actually_expanded = complete_with_user_dicts ();
                state = CompletionState.UserDictOnly;
                if (!actually_expanded) {
                    expand_completion ();
                } else {
                    expanded ();
                }
                break;
            case CompletionState.UserDictOnly:
                complete_with_non_user_dicts ();
                state = CompletionState.Full;
                expanded ();
                break;
            }
        }

        internal bool is_initialized {
            get {
                return state.is_initialized ();
            }
        }

        internal void init (string midasi, Gee.List<Dict> dicts) {
            clear_if_initialized ();

            this.dicts = dicts;
            this.midasi = midasi;
            this.state = CompletionState.None;
        }

        internal void init_with_limited_expansion (string midasi,
                                                   Gee.List<Dict> dicts,
                                                   int size)
        {
            init (midasi, dicts);
            complete_with_user_dicts_with_limit (size);
            expanded ();
            state = CompletionState.UserDictWithLimit;
        }

        internal string? next () {
            var new_idx = index + 1;
            if (new_idx >= completions.size && state.is_expandable ()) {
                expand_completion ();
            }

            if (new_idx < completions.size) {
                index = new_idx;
                return completions[index];
            } else {
                return null;
            }
        }

        internal string? previous () {
           var new_idx = index - 1;
           if (new_idx >= 0) {
               index = new_idx;
               return completions[index];
           } else {
               return null;
           }
        }

        internal Completer () {}

        internal enum CompletionState {
            Uninitialized, None, UserDictWithLimit, UserDictOnly, Full;

            internal bool is_initialized () {
                return this != Uninitialized;
            }

            internal bool is_expandable () {
                return this != Full;
            }
        }
    }

    public class CompletionList : Object {

        Completer completer;

        public int total_size {
            get {
                if (completer.state.is_expandable ())
                    return -1;
                else
                    return completer.completions.size;
            }
        }

        public int current_size {
            get {
                return completer.completions.size;
            }
        }

        public new string @get (int i) {
            return completer.completions[i];
        }

        public int cursor_pos {
            get{
                return completer.index;
            }
        }

        public signal void expanded ();
        void send_expanded () { expanded (); }

        public signal void index_moved ();
        void send_index_moved () { index_moved (); }

        public signal void cleared ();
        void send_cleared () { cleared (); }

        internal CompletionList (Completer completer) {
            this.completer = completer;
            completer.expanded.connect (send_expanded);
            completer.notify["index"].connect (send_index_moved);
            completer.cleared.connect (send_cleared);
        }
    }
}