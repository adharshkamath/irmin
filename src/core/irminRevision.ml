(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
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

type ('a, 'b) node = {
  tree   : 'a option;
  parents: 'b list;
}

module Revision (A: IrminBase.S) (B: IrminBase.S) = struct

  type t = (A.t, B.t) node

  module XTree = struct
    include IrminBase.Option(A)
    let name = "tree"
  end
  module XParents = struct
    include IrminBase.List(B)
    let name = "parents"
  end
  module XRevision = struct
    include IrminBase.Pair(XTree)(XParents)
    let name = "revision"
  end

  let name = XRevision.name

  let set buf t =
    XRevision.set buf (t.tree, t.parents)

  let get buf =
    let tree, parents = XRevision.get buf in
    { tree; parents }

  let sizeof t =
    XRevision.sizeof (t.tree, t.parents)

  let to_json t =
    XRevision.to_json (t.tree, t.parents)

  let of_json j =
    let tree, parents = XRevision.of_json j in
    { tree; parents }

  let to_string t =
    XRevision.to_string (t.tree, t.parents)

  let pretty t =
    XRevision.pretty (t.tree, t.parents)

  let hash t =
    XRevision.hash (t.tree, t.parents)

  let compare t1 t2 =
    XRevision.compare (t1.tree, t1.parents) (t2.tree, t2.parents)

  let equal t1 t2 =
    compare t1 t2 = 0

end

module type STORE = sig
  type key
  type tree
  type revision = (key, key) node
  include IrminBase.S with type t := revision
  module Graph: IrminGraph.S with type Vertex.t = revision
  include IrminStore.A with type key := key
                        and type value := revision
  val revision: t -> ?tree:tree -> revision list -> key Lwt.t
  val tree: t -> revision -> tree Lwt.t option
  val parents: t -> revision -> revision Lwt.t list
  val cut: t -> ?roots:key list -> key list -> Graph.t Lwt.t
end

module Make
    (K: IrminKey.S)
    (T: IrminTree.STORE with type key = K.t)
    (S: IrminStore.A with type key = K.t
                      and type value = (T.key, K.t) node) =
struct

  open Lwt

  type key = K.t

  type tree = T.tree

  type revision = (K.t, K.t) node

  type t = {
    t: T.t;
    r: S.t
  }

  let create () =
    T.create () >>= fun t ->
    S.create () >>= fun r ->
    return { t; r }

  let add t r =
    S.add t.r r

  let read t r =
    S.read t.r r

  let read_exn t r =
    S.read_exn t.r r

  let mem t r =
    S.mem t.r r

  let tree t r =
    match r.tree with
    | None   -> None
    | Some k -> Some (T.read_exn t.t k)

  let revision t ?tree parents =
    begin match tree with
      | None      -> return_none
      | Some tree -> T.add t.t tree >>= fun k -> return (Some k)
    end
    >>= fun tree ->
    Lwt_list.map_p (S.add t.r) parents
    >>= fun parents ->
    S.add t.r { tree; parents }

  let parents t r =
    List.map (read_exn t) r.parents

  module Revision = Revision(K)(K)

  include (Revision: IrminBase.S with type t := revision)

  module Graph = IrminGraph.Make(Revision)

  let cut t ?roots keys =
    Lwt_list.map_p (read_exn t) keys >>= fun keys ->
    let pred r =
      Lwt_list.map_p
        (fun r -> r)
        (parents t r) in
    begin match roots with
      | None    -> return_none
      | Some ks -> Lwt_list.map_p (read_exn t) ks >>= fun ts -> return (Some ts)
    end
    >>= fun roots ->
    Graph.closure ?roots pred keys

  let list t key =
    cut t [key] >>= fun g ->
    (* XXX: ugly *)
    Lwt_list.map_p (S.add t.r) (Graph.vertex g)

end
