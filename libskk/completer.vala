// todo: change file name to completion.vala
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

        void clear_if_initialized () {
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
        void add_completion (string candidate) {
            if (completion_set.add (candidate)) {
                completions.add (candidate);
            }
        }

        void complete_with_user_dicts () {
            foreach (var dict in dicts) {
                if (! (dict is UserDict)) continue;
                foreach (var candidate in dict.complete (midasi)) {
                    add_completion (candidate);
                }
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
            case CompletionState.Full:
                break;
            case CompletionState.Uninitialized:
                complete_with_user_dicts ();
                state = CompletionState.UserDictOnly;
                expanded ();
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
            expand_completion ();
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

        /* not used yet
           internal string? previous () {
           var new_idx = index - 1;
           if (new_idx >= 0) {
           index = new_idx;
           return completions[index];
           } else {
           return null;
           }
           }
        */

        internal Completer () {}

        internal enum CompletionState {
            Uninitialized, UserDictOnly, Full;

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