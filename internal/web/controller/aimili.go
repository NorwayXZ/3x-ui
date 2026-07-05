package controller

import (
	"net/http"
	"strconv"

	"github.com/mhsanaei/3x-ui/v3/internal/web/service"

	"github.com/gin-gonic/gin"
)

type AimiliController struct {
	BaseController
	aimiliService service.AimiliService
}

func NewAimiliAPIController(g *gin.RouterGroup) *AimiliController {
	a := &AimiliController{}
	a.initAPIRouter(g)
	return a
}

func NewAimiliConsoleController(g *gin.RouterGroup) *AimiliController {
	a := &AimiliController{}
	a.initConsoleRouter(g)
	return a
}

func (a *AimiliController) initAPIRouter(g *gin.RouterGroup) {
	g.GET("/status", a.status)
	g.GET("/favorites", a.favorites)
	g.GET("/console", a.consoleURL)
	g.GET("/logs", a.logs)
	g.POST("/start", a.start)
	g.POST("/stop", a.stop)
	g.POST("/restart", a.restart)
	g.POST("/nodes/:id/connect", a.connectNode)
}

func (a *AimiliController) initConsoleRouter(g *gin.RouterGroup) {
	panel := g.Group("/panel")
	panel.Use(a.checkLogin)
	panel.GET("/aimili-console", a.consoleIndex)
	panel.Any("/aimili-console/*path", a.proxyConsole)
}

func (a *AimiliController) status(c *gin.Context) {
	status, err := a.aimiliService.GetStatus(c.GetString("base_path"))
	jsonObj(c, status, err)
}

func (a *AimiliController) consoleURL(c *gin.Context) {
	status, err := a.aimiliService.GetStatus(c.GetString("base_path"))
	if err != nil {
		jsonObj(c, nil, err)
		return
	}
	jsonObj(c, gin.H{
		"url":       status.PreferredConsoleURL,
		"proxyUrl":  status.ConsoleProxyURL,
		"directUrl": status.ConsoleDirectURL,
	}, nil)
}

func (a *AimiliController) favorites(c *gin.Context) {
	result, err := a.aimiliService.GetFavorites()
	jsonObj(c, result, err)
}

func (a *AimiliController) logs(c *gin.Context) {
	lines, _ := strconv.Atoi(c.DefaultQuery("lines", "100"))
	result, err := a.aimiliService.GetLogs(lines)
	jsonObj(c, result, err)
}

func (a *AimiliController) start(c *gin.Context)   { a.runAction(c, "start") }
func (a *AimiliController) stop(c *gin.Context)    { a.runAction(c, "stop") }
func (a *AimiliController) restart(c *gin.Context) { a.runAction(c, "restart") }

func (a *AimiliController) connectNode(c *gin.Context) {
	result, err := a.aimiliService.ConnectNode(c.Param("id"), c.GetString("base_path"))
	jsonObj(c, result, err)
}

func (a *AimiliController) runAction(c *gin.Context, action string) {
	result, err := a.aimiliService.RunAction(action, c.GetString("base_path"))
	jsonObj(c, result, err)
}

func (a *AimiliController) consoleIndex(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	c.Redirect(http.StatusTemporaryRedirect, c.GetString("base_path")+"panel/aimili-console/")
}

func (a *AimiliController) proxyConsole(c *gin.Context) {
	proxy, err := a.aimiliService.BuildReverseProxy(c.GetString("base_path"))
	if err != nil {
		c.String(http.StatusBadGateway, "AimiliVPN console is unavailable: %v", err)
		return
	}

	for _, header := range []string{
		"Content-Security-Policy",
		"Referrer-Policy",
		"Strict-Transport-Security",
		"X-Content-Type-Options",
		"X-Frame-Options",
	} {
		c.Writer.Header().Del(header)
	}

	proxy.ServeHTTP(c.Writer, c.Request)
	c.Abort()
}
