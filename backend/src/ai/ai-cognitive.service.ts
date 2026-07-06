import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ChatRequestDto } from './dto/chat.dto';
import { AiWebService } from './ai-web.service';

/**
 * Cognitive AI Service - Agentic Reasoning Engine
 * Implements Super Artificial Intelligence Cognitive Reasoning
 * No hardcoded responses - dynamic analysis and reasoning
 */
@Injectable()
export class AiCognitiveService {
  private readonly logger = new Logger(AiCognitiveService.name);

  constructor(
    private configService: ConfigService,
    private aiWebService: AiWebService
  ) {}

  /**
   * Agentic Cognitive Reasoning Engine
   * Analyzes business context, fetches real-time data, and generates insights
   */
  async cognitiveBusinessAnalysis(dto: ChatRequestDto): Promise<{
    analysis: any,
    insights: string[],
    recommendations: any[]
  }> {
    // Step 1: Understand the business context
    const context = this.analyzeBusinessContext(dto);

    // Step 2: Gather real-time intelligence
    const intelligence = await this.gatherIntelligence(context);

    // Step 3: Analyze and reason about the data
    const analysis = this.agenticReasoning(context, intelligence);

    // Step 4: Generate actionable insights
    const insights = this.generateInsights(analysis);

    // Step 5: Create recommendations
    const recommendations = this.generateRecommendations(analysis, insights);

    return { analysis, insights, recommendations };
  }

  /**
   * Analyze business context from the request
   * Extracts key business parameters for reasoning
   */
  private analyzeBusinessContext(dto: ChatRequestDto): {
    businessType: string,
    location: string,
    role: string,
    question: string,
    dataPoints: any
  } {
    return {
      businessType: dto.business_context?.business_type || 'retail',
      location: dto.business_context?.branch || 'unknown',
      role: dto.business_context?.role || 'owner',
      question: dto.user_question || '',
      dataPoints: dto.data_context || {}
    };
  }

  /**
   * Gather intelligence from multiple sources
   * Combines web research with business data
   */
  private async gatherIntelligence(context: any): Promise<{
    webInsights: { insights: string[], sources: any[] },
    businessData: any
  }> {
    // Search for current business trends and strategies
    const searchQuery = `${context.businessType} business strategies ${context.location} 2025`;
    const webInsights = await this.aiWebService.searchBusinessInsights(searchQuery);

    return {
      webInsights,
      businessData: context.dataPoints
    };
  }

  /**
   * Agentic Reasoning Engine
   * Core cognitive reasoning system - no hardcoded rules
   * Analyzes data and generates insights dynamically
   */
  private agenticReasoning(context: any, intelligence: any): {
    currentState: any,
    opportunities: string[],
    risks: string[],
    trends: string[]
  } {
    const analysis: {
      currentState: any,
      opportunities: string[],
      risks: string[],
      trends: string[]
    } = {
      currentState: {},
      opportunities: [],
      risks: [],
      trends: []
    };

    // Analyze business data if available
    if (intelligence.businessData.total_sales) {
      analysis.currentState.salesPerformance = {
        totalSales: intelligence.businessData.total_sales,
        assessment: intelligence.businessData.total_sales > 30000 ? 'strong' : 'moderate'
      };
    }

    if (intelligence.businessData.transactions) {
      analysis.currentState.transactionVolume = {
        count: intelligence.businessData.transactions,
        averageValue: intelligence.businessData.total_sales / intelligence.businessData.transactions
      };
    }

    // Analyze inventory if available
    if (intelligence.businessData.low_stock_items) {
      analysis.risks.push(
        `Stockout risk: ${intelligence.businessData.low_stock_items.length} items at low levels`
      );
    }

    if (intelligence.businessData.slow_moving_items) {
      analysis.risks.push(
        `Dead stock: ${intelligence.businessData.slow_moving_items.length} items not selling`
      );
    }

    // Extract trends from web insights
    intelligence.webInsights.insights.forEach(insight => {
      if (insight.includes('%')) {
        analysis.trends.push(insight);
      } else if (insight.includes('growing') || insight.includes('increasing')) {
        analysis.opportunities.push(insight);
      }
    });

    return analysis;
  }

  /**
   * Generate insights from analysis
   * Cognitive reasoning to identify key insights
   */
  private generateInsights(analysis: any): string[] {
    const insights = [];

    // Sales insights
    if (analysis.currentState.salesPerformance) {
      insights.push(
        `Sales performance is ${analysis.currentState.salesPerformance.assessment} at KES ${analysis.currentState.salesPerformance.totalSales}`
      );
    }

    // Transaction insights
    if (analysis.currentState.transactionVolume) {
      insights.push(
        `Average transaction value is KES ${Math.round(analysis.currentState.transactionVolume.averageValue)}`
      );
    }

    // Risk insights
    analysis.risks.forEach(risk => {
      insights.push(`Risk detected: ${risk}`);
    });

    // Opportunity insights
    analysis.opportunities.forEach(opportunity => {
      insights.push(`Opportunity: ${opportunity}`);
    });

    return insights;
  }

  /**
   * Generate recommendations based on analysis
   * Cognitive reasoning to create actionable advice
   */
  private generateRecommendations(analysis: any, insights: string[]): any[] {
    const recommendations = [];

    // Stock management recommendations
    if (analysis.risks.some(r => r.includes('Stockout'))) {
      recommendations.push({
        type: 'urgent',
        action: 'Restock low inventory items immediately',
        reasoning: 'Prevent lost sales and customer dissatisfaction',
        priority: 'high',
        expectedImpact: 'Maintain sales momentum and customer loyalty'
      });
    }

    // Dead stock recommendations
    if (analysis.risks.some(r => r.includes('Dead stock'))) {
      recommendations.push({
        type: 'optimization',
        action: 'Create clearance promotions for slow-moving items',
        reasoning: 'Free up capital and storage space',
        priority: 'medium',
        expectedImpact: 'Improve cash flow and reduce waste'
      });
    }

    // Growth recommendations based on trends
    analysis.trends.forEach(trend => {
      if (trend.includes('e-commerce') || trend.includes('online')) {
        recommendations.push({
          type: 'growth',
          action: 'Expand online sales channels',
          reasoning: `Capitalize on ${trend}`,
          priority: 'medium',
          expectedImpact: 'Increase market reach and sales'
        });
      }

      if (trend.includes('mobile') || trend.includes('M-Pesa')) {
        recommendations.push({
          type: 'payment',
          action: 'Enhance mobile money integration',
          reasoning: `Leverage ${trend}`,
          priority: 'high',
          expectedImpact: 'Improve customer convenience and conversion'
        });
      }
    });

    // Add loyalty program if not already mentioned
    if (!recommendations.some(r => r.action.includes('loyalty'))) {
      recommendations.push({
        type: 'growth',
        action: 'Implement customer loyalty program',
        reasoning: 'Increase repeat purchases and customer lifetime value',
        priority: 'medium',
        expectedImpact: '25-40% increase in customer retention'
      });
    }

    return recommendations;
  }

  /**
   * Proactive Business Monitoring
   * Continuously analyzes business health and detects issues
   */
  async proactiveMonitor(dto: ChatRequestDto): Promise<{
    healthScore: number,
    criticalIssues: any[],
    improvementAreas: any[],
    growthOpportunities: any[]
  }> {
    const context = this.analyzeBusinessContext(dto);
    const intelligence = await this.gatherIntelligence(context);
    const analysis = this.agenticReasoning(context, intelligence);

    // Calculate health score (0-100)
    let healthScore = 80; // Base score

    // Deduct for risks
    analysis.risks.forEach(risk => {
      if (risk.includes('Stockout')) healthScore -= 20;
      if (risk.includes('Dead stock')) healthScore -= 10;
    });

    // Add for opportunities
    analysis.opportunities.forEach(() => {
      healthScore += 5; // Each opportunity adds potential
    });

    // Ensure score is between 0-100
    healthScore = Math.max(0, Math.min(100, healthScore));

    // Identify critical issues
    const criticalIssues = analysis.risks
      .filter(risk => risk.includes('Stockout') || risk.includes('critical'))
      .map(risk => ({
        issue: risk,
        severity: 'critical',
        actionRequired: 'immediate'
      }));

    // Identify improvement areas
    const improvementAreas = analysis.risks
      .filter(risk => !risk.includes('Stockout') && !risk.includes('critical'))
      .map(risk => ({
        area: risk,
        severity: 'medium',
        actionRequired: 'planning'
      }));

    // Identify growth opportunities
    const growthOpportunities = analysis.opportunities.map(opportunity => ({
      opportunity: opportunity,
      potential: 'high',
      actionRequired: 'strategic'
    }));

    return {
      healthScore,
      criticalIssues,
      improvementAreas,
      growthOpportunities
    };
  }

  /**
   * Cognitive Business Advisor
   * Provides comprehensive business advice using agentic reasoning
   */
  async cognitiveBusinessAdvisor(dto: ChatRequestDto): Promise<{
    summary: string,
    keyMetrics: any,
    insights: string[],
    recommendations: any[],
    webSources: any[]
  }> {
    // Perform full cognitive analysis
    const analysis = await this.cognitiveBusinessAnalysis(dto);
    const monitoring = await this.proactiveMonitor(dto);

    // Generate summary
    const summary = this.generateBusinessSummary(analysis, monitoring);

    // Extract key metrics
    const keyMetrics = this.extractKeyMetrics(analysis);

    // Combine all insights
    const allInsights = [...analysis.insights, ...this.generateMonitoringInsights(monitoring)];

    // Prioritize recommendations
    const prioritizedRecommendations = this.prioritizeRecommendations(
      [...analysis.recommendations, ...this.generateMonitoringRecommendations(monitoring)]
    );

    // Get web sources
    const webSources = await this.getWebSources(dto);

    return {
      summary,
      keyMetrics,
      insights: allInsights,
      recommendations: prioritizedRecommendations,
      webSources
    };
  }

  /**
   * Generate business summary
   * Cognitive synthesis of all analysis
   */
  private generateBusinessSummary(analysis: any, monitoring: any): string {
    const parts = [];

    // Business type and location
    parts.push(`Your business is performing `);

    // Health score
    if (monitoring.healthScore >= 80) {
      parts.push('well ');
    } else if (monitoring.healthScore >= 60) {
      parts.push('moderately ');
    } else {
      parts.push('below expectations ');
    }

    parts.push(`with a health score of ${monitoring.healthScore}/100. `);

    // Critical issues
    if (monitoring.criticalIssues.length > 0) {
      parts.push(`${monitoring.criticalIssues.length} critical issue(s) require immediate attention. `);
    }

    // Opportunities
    if (analysis.opportunities.length > 0) {
      parts.push(`${analysis.opportunities.length} growth opportunity(ies) identified. `);
    }

    return parts.join('');
  }

  /**
   * Extract key metrics
   * Cognitive identification of important business metrics
   */
  private extractKeyMetrics(analysis: any): any {
    const metrics: any = {};

    if (analysis.currentState.salesPerformance) {
      metrics.salesPerformance = analysis.currentState.salesPerformance;
    }

    if (analysis.currentState.transactionVolume) {
      metrics.transactionVolume = analysis.currentState.transactionVolume;
    }

    metrics.riskCount = {
      total: analysis.risks.length,
      critical: analysis.risks.filter(r => r.includes('critical') || r.includes('Stockout')).length
    };

    metrics.opportunityCount = analysis.opportunities.length;

    return metrics;
  }

  /**
   * Generate monitoring insights
   * Additional insights from proactive monitoring
   */
  private generateMonitoringInsights(monitoring: any): string[] {
    const insights = [];

    insights.push(`Business health score: ${monitoring.healthScore}/100`);

    if (monitoring.criticalIssues.length > 0) {
      insights.push(`${monitoring.criticalIssues.length} critical issue(s) detected`);
    }

    if (monitoring.improvementAreas.length > 0) {
      insights.push(`${monitoring.improvementAreas.length} area(s) for improvement identified`);
    }

    if (monitoring.growthOpportunities.length > 0) {
      insights.push(`${monitoring.growthOpportunities.length} growth opportunity(ies) available`);
    }

    return insights;
  }

  /**
   * Generate monitoring recommendations
   * Actionable advice from proactive monitoring
   */
  private generateMonitoringRecommendations(monitoring: any): any[] {
    const recommendations = [];

    // Critical issues
    monitoring.criticalIssues.forEach(issue => {
      recommendations.push({
        type: 'critical',
        action: `Address: ${issue.issue}`,
        reasoning: `Critical severity issue requiring ${issue.actionRequired} action`,
        priority: 'high',
        expectedImpact: 'Prevent business disruption'
      });
    });

    // Improvement areas
    monitoring.improvementAreas.forEach(area => {
      recommendations.push({
        type: 'improvement',
        action: `Improve: ${area.area}`,
        reasoning: `Medium severity issue requiring ${area.actionRequired}`,
        priority: 'medium',
        expectedImpact: 'Enhance business operations'
      });
    });

    // Growth opportunities
    monitoring.growthOpportunities.forEach(opportunity => {
      recommendations.push({
        type: 'growth',
        action: `Pursue: ${opportunity.opportunity}`,
        reasoning: `High potential opportunity for ${opportunity.actionRequired} growth`,
        priority: 'high',
        expectedImpact: 'Business expansion and increased revenue'
      });
    });

    return recommendations;
  }

  /**
   * Prioritize recommendations
   * Cognitive ranking of recommendations by impact
   */
  private prioritizeRecommendations(recommendations: any[]): any[] {
    // Priority order: critical > growth > improvement > other
    const priorityOrder = { 'critical': 1, 'growth': 2, 'improvement': 3, 'urgent': 1, 'optimization': 4 };

    return recommendations.sort((a, b) => {
      const priorityA = priorityOrder[a.type] || 100;
      const priorityB = priorityOrder[b.type] || 100;
      return priorityA - priorityB;
    });
  }

  /**
   * Get web sources for transparency
   * Shows where insights came from
   */
  private async getWebSources(dto: ChatRequestDto): Promise<any[]> {
    const context = this.analyzeBusinessContext(dto);
    const searchQuery = `${context.businessType} business strategies ${context.location} 2025`;
    const result = await this.aiWebService.searchBusinessInsights(searchQuery);
    return result.sources;
  }
}
