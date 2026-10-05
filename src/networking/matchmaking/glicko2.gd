class_name Glicko2
extends RefCounted
## Glicko-2 rating math (Glickman, "Example of the Glicko-2 system", 2013).
## Pure static functions; ratings on the public scale (1500 / 350 / 0.06).
##
## One match is one rating period. A term is {g, e, s}: the opponent's
## g(phi), the expected score E and the actual score s (1 win, 0 loss).
##
##   mu = (r - 1500) / 173.7178          phi = RD / 173.7178
##   g(phi) = 1 / sqrt(1 + 3 phi^2 / pi^2)
##   E      = 1 / (1 + exp(-g(phi_j) (mu - mu_j)))
##   v      = 1 / sum(g^2 E (1 - E))
##   delta  = v * sum(g (s - E))
##   sigma' = Illinois root of f(x) (paper step 5, eps 1e-6)
##   phi*   = sqrt(phi^2 + sigma'^2)
##   phi'   = 1 / sqrt(1/phi*^2 + 1/v)
##   mu'    = mu + phi'^2 * sum(g (s - E))
##
## Worked example (paper): 1500/200/0.06 vs 1400/30 (win), 1550/100 (loss),
## 1700/300 (loss), tau 0.5 -> 1464.05 / 151.52 / 0.059996.

const SCALE: float = 173.7178
const CENTER: float = 1500.0
const EPSILON: float = 0.000001


static func to_mu(rating: float) -> float:
	return (rating - CENTER) / SCALE


static func to_phi(rd: float) -> float:
	return rd / SCALE


static func g(phi: float) -> float:
	return 1.0 / sqrt(1.0 + 3.0 * phi * phi / (PI * PI))


## Expected score of mu against an opponent (mu_j, with g_j = g(phi_j)).
static func expected(mu: float, mu_j: float, g_j: float) -> float:
	return 1.0 / (1.0 + exp(-g_j * (mu - mu_j)))


## A term against one opponent given on the public scale.
static func term_vs(rating: float, opp_rating: float, opp_rd: float, score: float) -> Dictionary:
	var gj := g(to_phi(opp_rd))
	return {"g": gj, "e": expected(to_mu(rating), to_mu(opp_rating), gj), "s": score}


## Updates one player from `terms`. Returns {rating, rd, vol} on the public
## scale. No terms: only the deviation grows (an idle period).
static func update(rating: float, rd: float, vol: float, terms: Array, tau: float) -> Dictionary:
	var mu := to_mu(rating)
	var phi := to_phi(rd)
	if terms.is_empty():
		return {"rating": rating, "rd": sqrt(phi * phi + vol * vol) * SCALE, "vol": vol}
	var inv_v := 0.0
	var sum_gs := 0.0
	for t in terms:
		var gj: float = t.g
		var e: float = t.e
		inv_v += gj * gj * e * (1.0 - e)
		sum_gs += gj * (float(t.s) - e)
	var v := 1.0 / inv_v
	var delta := v * sum_gs
	var new_vol := _new_volatility(phi, vol, v, delta, tau)
	var phi_star := sqrt(phi * phi + new_vol * new_vol)
	var new_phi := 1.0 / sqrt(1.0 / (phi_star * phi_star) + 1.0 / v)
	var new_mu := mu + new_phi * new_phi * sum_gs
	return {"rating": CENTER + SCALE * new_mu, "rd": SCALE * new_phi, "vol": new_vol}


static func _new_volatility(phi: float, sigma: float, v: float, delta: float, tau: float) -> float:
	var a := log(sigma * sigma)
	var f := func(x: float) -> float:
		var ex := exp(x)
		var d := phi * phi + v + ex
		return ex * (delta * delta - phi * phi - v - ex) / (2.0 * d * d) - (x - a) / (tau * tau)
	var big_a := a
	var big_b: float
	if delta * delta > phi * phi + v:
		big_b = log(delta * delta - phi * phi - v)
	else:
		var k := 1
		while f.call(a - k * tau) < 0.0 and k < 100:
			k += 1
		big_b = a - k * tau
	var fa: float = f.call(big_a)
	var fb: float = f.call(big_b)
	var guard := 0
	while absf(big_b - big_a) > EPSILON and guard < 200:
		guard += 1
		var c := big_a + (big_a - big_b) * fa / (fb - fa)
		var fc: float = f.call(c)
		if fc * fb <= 0.0:
			big_a = big_b
			fa = fb
		else:
			fa /= 2.0
		big_b = c
		fb = fc
	return exp(big_a / 2.0)
