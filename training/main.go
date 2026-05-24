package main

import "fmt"

func add(a, b int) int {
	return a + b
}

func main() {
	a, b := 3, 5
	fmt.Printf("%d + %d = %d\n", a, b, add(a, b))
}
