type BlockedBox =
  | BlockedBox { data: tensor[2, f32], tag: string }
def blocked_tag_of(b: BlockedBox) -> string =
  match b with {
    | BlockedBox { data, tag } => tag
  }
def blocked_wildcard_discard() -> string = {
  b = BlockedBox { data: to_tensor([cast(1.0, f32), cast(2.0, f32)]), tag: "t" }
  _ = blocked_tag_of(b)
  blocked_tag_of(b)
}
