using Gee;

namespace Skk {

    class Completer : Object {

        unowned Gee.List<Dict> dicts;
        CompletionState state = CompletionState.Uninitialized;
        string midasi;
        int index = -1;
        Gee.List<string> completions = new ArrayList<string> ();
        Gee.Set<string> completion_set = new HashSet<string> ();

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
            case CompletionState.Uninitialized:
                complete_with_user_dicts ();
                state = CompletionState.UserDictOnly;
                if (completions.size <= 0) {
                    expand_completion ();
                }
                break;
            case CompletionState.UserDictOnly:
                complete_with_non_user_dicts ();
                state = CompletionState.Full;
                break;
            case CompletionState.Full:
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

        enum CompletionState {
            Uninitialized, UserDictOnly, Full;

            public bool is_initialized () {
                return this != Uninitialized;
            }

            public bool is_expandable () {
                return this != Full;
            }
        }
    }
}