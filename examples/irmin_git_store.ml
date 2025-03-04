(*
 * Copyright (c) 2013-2021 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

(* Simple example of reading and writing in a Git repository *)

open Lwt.Syntax

let info = Irmin_unix.info

module Store = Irmin_unix.Git.FS.KV (Irmin.Contents.String)

let update t k v =
  let msg = Fmt.str "Updating /%s" (String.concat "/" k) in
  print_endline msg;
  Store.set_exn t ~info:(info "%s" msg) k v

let read_exn t k =
  let msg = Fmt.str "Reading /%s" (String.concat "/" k) in
  print_endline msg;
  Store.get t k

let main () =
  Config.init ();
  let config = Irmin_git.config ~bare:true Config.root in
  let* repo = Store.Repo.v config in
  let* t = Store.main repo in
  let* () = update t [ "root"; "misc"; "1.txt" ] "Hello world!" in
  let* () = update t [ "root"; "misc"; "2.txt" ] "Hi!" in
  let* () = update t [ "root"; "misc"; "3.txt" ] "How are you ?" in
  let* _ = read_exn t [ "root"; "misc"; "2.txt" ] in
  let* x = Store.clone ~src:t ~dst:"test" in
  print_endline "cloning ...";
  let* () = update t [ "root"; "misc"; "3.txt" ] "Hohoho" in
  let* () = update x [ "root"; "misc"; "2.txt" ] "Cool!" in
  let* r = Store.merge_into ~info:(info "t: Merge with 'x'") x ~into:t in
  match r with
  | Error _ -> failwith "conflict!"
  | Ok () ->
      print_endline "merging ...";
      let* _ = read_exn t [ "root"; "misc"; "2.txt" ] in
      let+ _ = read_exn t [ "root"; "misc"; "3.txt" ] in
      ()

let () =
  Printf.printf
    "This example creates a Git repository in %s and use it to read \n\
     and write data:\n"
    Config.root;
  let _ = Sys.command (Printf.sprintf "rm -rf %s" Config.root) in
  Lwt_main.run (main ());
  Printf.printf "You can now run `cd %s && tig` to inspect the store.\n"
    Config.root
