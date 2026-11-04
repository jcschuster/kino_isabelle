theory Fixture imports Main begin

(* lemma inside (* nested *) comment by *)
text ‹lemma ‹nested by› done›
text \<open>lemma \<open>by\<close> done\<close>
lemma foo[simp]: "lemma by \<forall>x. x = x" (is "?P")
  by simp
thm foo.induct HOL.simp_thms
definition "f x = x + 1.5"
lemma "`lemma` = x" {* lemma
  by *}
proof -
  { fix x :: 'a
    have "x = x" ..
  }
  show ?thesis \<proof>
qed
― ‹comment lemma›
\<comment> \<open>lemma\<close>
end
